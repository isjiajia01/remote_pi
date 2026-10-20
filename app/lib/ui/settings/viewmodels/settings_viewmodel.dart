import 'dart:async';

import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/domain/value_objects/semver.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/settings/states/settings_state.dart';

/// Settings is config-only (nickname + revoke). The peer switcher moved
/// to Home; the connection itself is shared and owned by
/// [ConnectionManager] from app boot (plano 12). Revoke side-effect:
/// re-subscribe the relay's presence push so the removed epk is dropped.
class SettingsViewModel extends ViewModel<SettingsState> {
  final PairingStorage _storage;
  final Preferences _prefs;
  final ConnectionManager _conn;

  /// Optional in tests; required in production. The revoke flow drives
  /// it explicitly with `allowEmpty:true` so a revoke of the last
  /// remaining peer still propagates to the relay — without it, the
  /// safety net in [MeshSyncService] refuses to publish members=[] and
  /// the next `pullOnDemand` resurrects the peer from the stale blob.
  final MeshSyncService? _meshSync;
  bool _disposed = false;

  SettingsViewModel(
    this._storage,
    this._prefs,
    this._conn,
    this._reachability, {
    MeshSyncService? meshSync,
    UpdateChecker? updateChecker,
    UrlOpener? urlOpener,
    this.appVersion = 'Unknown',
    this.buildNumber = '',
    this.updatesEnabled = false,
  }) : _meshSync = meshSync,
       _updateChecker = updateChecker,
       _urlOpener = urlOpener,
       super(const SettingsLoading()) {
    _load();
    _presenceSub = _conn.presenceStream.listen((_) => _refreshPresence());
    _statusSub = _conn.statusStream.listen((_) => _refreshPresence());
    unawaited(checkCurrentRelay());
  }

  final RelayReachability _reachability;
  final UpdateChecker? _updateChecker;
  final UrlOpener? _urlOpener;
  final String appVersion;
  final String buildNumber;
  final bool updatesEnabled;
  late final StreamSubscription<Object> _presenceSub;
  late final StreamSubscription<Object> _statusSub;
  int _relayRequest = 0;
  String? _updateUrl;

  void _refreshPresence() {
    if (!_disposed) notifyListeners();
  }

  AgentStatus statusFor(String epk) => _conn.status is! StatusOnline
      ? AgentStatus.checking
      : switch (_conn.presenceFor(epk)) {
          PresenceOnline() => AgentStatus.online,
          PresenceOffline() => AgentStatus.offline,
          PresenceUnknown() => AgentStatus.checking,
        };

  Future<String> checkForUpdates() async {
    if (!updatesEnabled) return 'Updates come from TestFlight / the App Store';
    final latest = await _updateChecker?.fetchLatest();
    if (_disposed) return '';
    _updateUrl = null;
    if (latest == null) return "Couldn't check for updates. Try again.";
    if (!isNewerVersion(latest.version, appVersion)) {
      return 'You’re up to date.';
    }
    _updateUrl =
        latest
            .artifactFor(platform: 'android', format: 'apk', arch: 'universal')
            ?.url ??
        'https://remote-pi.jacobmoura.work/download';
    return 'Version ${latest.version} is available.';
  }

  bool get hasUpdate => _updateUrl != null;

  Future<void> openUpdate() async {
    final url = _updateUrl;
    if (url != null) await _urlOpener?.open(url);
  }

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(SettingsNoPeer(relay: state.relay));
      return;
    }
    emit(SettingsList(peers: peers, relay: state.relay));
  }

  /// Set or clear the local nickname for the peer at [epk].
  Future<void> setNickname(String epk, String? nickname) async {
    final s = state;
    if (s is! SettingsList) return;
    PeerRecord? target;
    for (final p in s.peers) {
      if (p.remoteEpk == epk) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    final trimmed = nickname?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final updated = target.copyWith(nickname: normalized);
    await _storage.savePeer(updated);
    await _load();
  }

  /// Effective relay URL the app is connecting to right now.
  String get effectiveRelayUrl => resolveRelayUrl(_prefs);

  /// User-set override for the relay URL. If `null`, the app is using the
  /// default endpoint [kDefaultRelayUrl].
  String get relayUrlOverride => _prefs.relayUrl ?? kDefaultRelayUrl;

  Future<RelayCheckResult> _check(String url) => _reachability
      .check(url)
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            const RelayCheckResult.failed(RelayCheckFailure.timeout),
      );

  String _failureMessage(RelayCheckFailure failure) =>
      failure == RelayCheckFailure.timeout
      ? 'No answer in 8 s.'
      : "Can't reach this host. On Tailscale? Check the VPN is on.";

  Future<void> checkCurrentRelay() async {
    final request = ++_relayRequest;
    emit(
      state.withRelay(
        const SettingsRelayState(status: SettingsRelayStatus.checking),
      ),
    );
    final result = await _check(effectiveRelayUrl);
    if (_disposed || request != _relayRequest) return;
    emit(
      state.withRelay(
        SettingsRelayState(
          status: result.failure == null
              ? SettingsRelayStatus.reachable
              : SettingsRelayStatus.failed,
          message: result.failure == null
              ? null
              : _failureMessage(result.failure!),
          latencyMs: result.elapsed?.inMilliseconds,
        ),
      ),
    );
  }

  Future<String?> saveRelayUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (!isValidRelayUrl(trimmed)) {
      final message =
          trimmed.startsWith('ws://') || trimmed.startsWith('wss://')
          ? kRelayUrlInvalidScheme
          : 'Enter a full URL starting with https://';
      // Invalid drafts do not change the saved relay’s reachability dot.
      return message;
    }
    final request = ++_relayRequest;
    emit(
      state.withRelay(
        const SettingsRelayState(status: SettingsRelayStatus.checking),
      ),
    );
    final result = await _check(trimmed);
    if (_disposed || request != _relayRequest) return 'Relay check cancelled.';
    if (result.failure != null) {
      // The failure belongs to the draft, not the saved host in Settings.
      unawaited(checkCurrentRelay());
      return _failureMessage(result.failure!);
    }
    try {
      await _prefs.setRelayUrl(trimmed == kDefaultRelayUrl ? null : trimmed);
    } catch (_) {
      if (!_disposed) unawaited(checkCurrentRelay());
      return "Couldn't save the relay. Try again.";
    }
    if (_disposed) return null;
    emit(
      state.withRelay(
        SettingsRelayState(
          status: SettingsRelayStatus.reachable,
          latencyMs: result.elapsed!.inMilliseconds,
          message: 'Saved · reachable ${result.elapsed!.inMilliseconds} ms',
        ),
      ),
    );
    await _conn.disconnect();
    unawaited(_conn.boot(preferredEpk: _prefs.selectedPeerEpk));
    return null;
  }

  /// Revoke pairing locally. Drops the peer from the relay's presence
  /// subscription too so we stop receiving updates about a peer that no
  /// longer exists on this device. Clears the selected pointer when it
  /// matches. If this was the LAST peer, also resets
  /// `onboardingCompleted=false` so the next boot lands on /onboarding
  /// (matches user expectation of "revoke = start fresh").
  Future<void> revoke(String epk) async {
    final wasActive = _conn.activePeer?.remoteEpk == epk;
    if (_prefs.selectedPeerEpk == epk) {
      await _prefs.setSelectedPeerEpk(null);
    }
    // Use the SILENT delete so the storage mutation hook does not
    // auto-publish a members=[] blob through the safety-net guard
    // (which would refuse it for the last-peer case and leave the
    // relay holding stale state). We publish ourselves below with
    // `allowEmpty:true` — the only place in the app that opts out of
    // the empty-on-existing safety net.
    await _storage.deletePeerSilent(epk);
    final remaining = await _storage.listPeers();
    if (_meshSync != null) {
      // ignore: unawaited_futures
      _meshSync.publish(allowEmpty: remaining.isEmpty);
    }
    _conn.subscribeToPeers(remaining.map((p) => p.remoteEpk).toList());
    // If the revoked peer was the one currently driving the connection,
    // tear it down so we don't keep talking to a peer the user just
    // removed. If others remain, fall back to one of them; otherwise
    // disconnect cleanly.
    if (wasActive) {
      await _conn.disconnect();
      if (remaining.isNotEmpty) {
        final fallback = remaining.first;
        await _prefs.setSelectedPeerEpk(fallback.remoteEpk);
        // ignore: unawaited_futures
        _conn.boot(preferredEpk: fallback.remoteEpk);
      }
    }
    if (remaining.isEmpty) {
      await _prefs.setOnboardingCompleted(false);
    }
    await _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _relayRequest++;
    unawaited(_presenceSub.cancel());
    unawaited(_statusSub.cancel());
    super.dispose();
  }
}
