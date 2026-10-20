import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/domain/entities/update_info.dart';
import 'package:flutter/services.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopTransport implements PeerTransport {
  @override
  Future<void> send(Uint8List data) async {}
  @override
  Future<Uint8List> receive() => Completer<Uint8List>().future;
  @override
  Future<void> close() async {}
}

PlainPeerChannel _channel() => PlainPeerChannel(transport: _NoopTransport());

ConnectionManager _conn({_FakeStorage? storage}) {
  return ConnectionManager(
    factory: (_, _) async => _channel(),
    storage: storage ?? _FakeStorage([]),
  );
}

class _FakeStorage extends PairingStorage {
  List<PeerRecord> peers;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => List.of(peers);

  @override
  Future<void> savePeer(PeerRecord r) async {
    peers = [r, ...peers.where((p) => p.remoteEpk != r.remoteEpk)];
  }

  @override
  Future<void> deletePeer(String epk) async {
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }

  @override
  Future<void> deletePeerSilent(String epk) async {
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool failWrites = false;
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) throw PlatformException(code: 'storage_unavailable');
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PeerRecord _peerA() => const PeerRecord(
  remoteEpk: 'epk_A',
  sessionName: 'Pi A',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _Reachability implements RelayReachability {
  RelayCheckResult result = const RelayCheckResult.reachable(
    Duration(milliseconds: 120),
  );
  final urls = <String>[];
  @override
  Future<RelayCheckResult> check(String url) async {
    urls.add(url);
    return result;
  }
}

class _UpdateChecker implements UpdateChecker {
  UpdateInfo? latest;
  int calls = 0;
  @override
  Future<UpdateInfo?> fetchLatest() async {
    calls++;
    return latest;
  }
}

class _UrlOpener implements UrlOpener {
  String? opened;
  @override
  Future<bool> open(String url) async {
    opened = url;
    return true;
  }
}

void main() {
  group('SettingsViewModel', () {
    test('initial state is SettingsLoading', () {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      expect(vm.state, isA<SettingsLoading>());
      vm.dispose();
    });

    test('empty storage → SettingsNoPeer', () async {
      final storage = _FakeStorage([]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<SettingsNoPeer>());
      vm.dispose();
    });

    test('peers loaded → SettingsList', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      final s = vm.state as SettingsList;
      expect(s.peers.single.remoteEpk, 'epk_A');

      vm.dispose();
    });

    test(
      'revoke deletes peer + clears selectedPeerEpk if it matched',
      () async {
        final storage = _FakeStorage([_peerA()]);
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setSelectedPeerEpk('epk_A');

        final vm = SettingsViewModel(
          storage,
          prefs,
          _conn(storage: storage),
          _Reachability(),
        );
        await Future<void>.delayed(Duration.zero);

        await vm.revoke('epk_A');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(storage.peers, isEmpty);
        expect(prefs.selectedPeerEpk, isNull);
        expect(vm.state, isA<SettingsNoPeer>());

        vm.dispose();
      },
    );

    test('revoke does NOT touch selectedPeerEpk if different', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk('epk_other');

      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      await vm.revoke('epk_A');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(prefs.selectedPeerEpk, 'epk_other');

      vm.dispose();
    });

    test('setNickname updates state and storage', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final s = vm.state as SettingsList;
      expect(s.peers.single.nickname, 'Casa');
      expect(storage.peers.single.nickname, 'Casa');

      vm.dispose();
    });

    test('setNickname with null clears the nickname', () async {
      final storage = _FakeStorage([_peerA().copyWith(nickname: 'Casa')]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);
      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname with whitespace clears the nickname', () async {
      final storage = _FakeStorage([_peerA().copyWith(nickname: 'Casa')]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', '   ');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname is a no-op for unknown epk', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        storage,
        prefs,
        _conn(storage: storage),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_does_not_exist', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });
  });

  group('SettingsViewModel — plan 14 relay config', () {
    test(
      'saveRelayUrl with valid URL persists override + returns null',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          _Reachability(),
        );
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('https://custom.example');
        expect(err, isNull);
        expect(prefs.relayUrl, 'https://custom.example');
        expect(vm.effectiveRelayUrl, 'https://custom.example');

        vm.dispose();
      },
    );

    test(
      'saveRelayUrl with invalid URL returns error and does NOT persist',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          _Reachability(),
        );
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('not-a-url');
        expect(err, isNotNull);
        expect(prefs.relayUrl, isNull);

        vm.dispose();
      },
    );

    test(
      'saveRelayUrl rejects ws:// / wss:// with the scheme-specific hint',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          _Reachability(),
        );
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('wss://relay.example');
        expect(err, isNotNull);
        expect(err, contains('ws://'));
        expect(err, contains('http://'));
        expect(prefs.relayUrl, isNull);

        vm.dispose();
      },
    );

    test('saveRelayUrl with empty / null is rejected (URL is now required) and '
        'does NOT clear the existing override', () async {
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setRelayUrl('https://x.example');
      final vm = SettingsViewModel(
        _FakeStorage([]),
        prefs,
        _conn(),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      // Empty → error, override untouched.
      final emptyErr = await vm.saveRelayUrl('');
      expect(emptyErr, isNotNull);
      expect(prefs.relayUrl, 'https://x.example');

      // Whitespace-only → same (trimmed to empty).
      final blankErr = await vm.saveRelayUrl('   ');
      expect(blankErr, isNotNull);
      expect(prefs.relayUrl, 'https://x.example');

      // null → same.
      final nullErr = await vm.saveRelayUrl(null);
      expect(nullErr, isNotNull);
      expect(prefs.relayUrl, 'https://x.example');

      vm.dispose();
    });

    test('relayUrlOverride defaults to kDefaultRelayUrl (pre-fill for the '
        '"use default" button) and reflects a saved override', () async {
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(
        _FakeStorage([]),
        prefs,
        _conn(),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);

      // No override yet → the field pre-fills with the default endpoint.
      expect(vm.relayUrlOverride, kDefaultRelayUrl);
      expect(vm.effectiveRelayUrl, kDefaultRelayUrl);

      // Saving the default URL explicitly is valid (what the button does).
      final err = await vm.saveRelayUrl(kDefaultRelayUrl);
      expect(err, isNull);
      expect(vm.relayUrlOverride, kDefaultRelayUrl);
      expect(prefs.relayUrl, isNull);

      vm.dispose();
    });
    test(
      'failed check preserves onboarding relay and reports specific errors',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setRelayUrl('https://onboarding.example');
        final check = _Reachability();
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn(), check);
        await Future<void>.delayed(Duration.zero);
        expect(vm.effectiveRelayUrl, 'https://onboarding.example');
        for (final failure in RelayCheckFailure.values) {
          check.result = RelayCheckResult.failed(failure);
          final error = await vm.saveRelayUrl('https://new.example');
          expect(
            error,
            failure == RelayCheckFailure.timeout
                ? 'No answer in 8 s.'
                : "Can't reach this host. On Tailscale? Check the VPN is on.",
          );
          expect(vm.effectiveRelayUrl, 'https://onboarding.example');
          expect(prefs.relayUrl, 'https://onboarding.example');
        }
        vm.dispose();
      },
    );

    test(
      'successful community reset clears override and records latency',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setRelayUrl('https://onboarding.example');
        final check = _Reachability();
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn(), check);
        await Future<void>.delayed(Duration.zero);
        expect(await vm.saveRelayUrl(kDefaultRelayUrl), isNull);
        expect(check.urls.last, kDefaultRelayUrl);
        expect(prefs.relayUrl, isNull);
        expect(vm.effectiveRelayUrl, kDefaultRelayUrl);
        expect(vm.state.relay.message, 'Saved · reachable 120 ms');
        vm.dispose();
      },
    );
    test('storage failure keeps the previous persisted relay', () async {
      final storage = _FakeSecureStorage();
      final prefs = Preferences(storage);
      await prefs.setRelayUrl('https://onboarding.example');
      storage.failWrites = true;
      final vm = SettingsViewModel(
        _FakeStorage([]),
        prefs,
        _conn(),
        _Reachability(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await vm.saveRelayUrl('https://new.example'),
        "Couldn't save the relay. Try again.",
      );
      expect(prefs.relayUrl, 'https://onboarding.example');
      expect(storage._store['prefs.relay_url'], 'https://onboarding.example');
      vm.dispose();
    });

    test(
      'manual Android update check offers current release link; iOS skips check',
      () async {
        final checker = _UpdateChecker();
        final opener = _UrlOpener();
        final prefs = Preferences(_FakeSecureStorage());
        final ios = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          _Reachability(),
          updateChecker: checker,
        );
        expect(
          await ios.checkForUpdates(),
          'Updates come from TestFlight / the App Store',
        );
        expect(checker.calls, 0);
        ios.dispose();
        final vm = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          _Reachability(),
          updateChecker: checker,
          urlOpener: opener,
          updatesEnabled: true,
          appVersion: '1.2.0',
        );
        expect(
          await vm.checkForUpdates(),
          "Couldn't check for updates. Try again.",
        );
        checker.latest = const UpdateInfo(
          version: '1.3.0',
          date: '',
          notes: '',
          artifacts: [
            UpdateArtifact(
              platform: 'android',
              arch: 'universal',
              format: 'apk',
              url: 'https://example.com/app.apk',
              sha256: '',
              size: 0,
            ),
          ],
        );
        expect(await vm.checkForUpdates(), 'Version 1.3.0 is available.');
        expect(vm.hasUpdate, isTrue);
        await vm.openUpdate();
        expect(opener.opened, 'https://example.com/app.apk');
        checker.latest = const UpdateInfo(
          version: '1.2.0',
          date: '',
          notes: '',
          artifacts: [],
        );
        expect(await vm.checkForUpdates(), 'You’re up to date.');
        expect(vm.hasUpdate, isFalse);
        vm.dispose();
      },
    );
  });
}
