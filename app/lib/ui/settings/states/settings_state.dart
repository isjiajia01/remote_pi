import 'package:app/pairing/storage.dart';
import 'package:flutter/foundation.dart' show listEquals;

enum SettingsRelayStatus { unknown, checking, reachable, failed }

class SettingsRelayState {
  const SettingsRelayState({
    this.status = SettingsRelayStatus.unknown,
    this.message,
    this.latencyMs,
  });

  final SettingsRelayStatus status;
  final String? message;
  final int? latencyMs;
}

sealed class SettingsState {
  const SettingsState({this.relay = const SettingsRelayState()});

  final SettingsRelayState relay;

  SettingsState withRelay(SettingsRelayState relay) => switch (this) {
    SettingsLoading() => SettingsLoading(relay: relay),
    SettingsNoPeer() => SettingsNoPeer(relay: relay),
    SettingsList(:final peers) => SettingsList(peers: peers, relay: relay),
  };
}

class SettingsLoading extends SettingsState {
  const SettingsLoading({super.relay});
}

class SettingsNoPeer extends SettingsState {
  const SettingsNoPeer({super.relay});
}

/// Machine configuration; active-session selection stays on the Dashboard.
class SettingsList extends SettingsState {
  const SettingsList({required this.peers, super.relay});

  final List<PeerRecord> peers;

  @override
  bool operator ==(Object other) =>
      other is SettingsList &&
      listEquals(other.peers, peers) &&
      other.relay == relay;

  @override
  int get hashCode => Object.hash(Object.hashAll(peers), relay);
}
