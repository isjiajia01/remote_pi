import 'package:app/data/repositories/control_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/uuid7.dart';

/// Ends phone-created Pi sessions through the machine's perch-sessiond
/// (`perch-control` room, `sessions.stop`; pi-extension/docs/mobile-sessions.md).
/// Only the creating phone is authorized; terminal sessions are never
/// addressable here.
class PhoneSessionControl {
  PhoneSessionControl(this._conn);
  final ConnectionManager _conn;

  Future<void> stop(PeerRecord peer, String sessionId) async {
    // No-op when this machine is already the active, online peer.
    await _conn.switchTo(peer);
    if (_conn.activePeer?.remoteEpk != peer.remoteEpk ||
        _conn.channel == null) {
      throw const ControlFailure('offline', 'Machine unavailable');
    }
    final client = ControlRepository(_conn);
    try {
      final capabilities = await client.capabilities();
      if (!capabilities.methods.contains('sessions.stop')) {
        throw const ControlFailure('unsupported', 'Session service missing');
      }
      await client.execute(
        ControlAction('session_${uuid7()}', 'sessions.stop', {
          'session_id': sessionId,
        }, null),
      );
    } finally {
      client.dispose();
    }
  }
}
