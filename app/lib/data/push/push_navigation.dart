import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';

/// Pushes contain navigation hints only. All connection details come from local pairings.
class PushNavigation {
  PushNavigation(this._storage, this._conn);
  final PairingStorage _storage;
  final ConnectionManager _conn;
  int _generation = 0;

  Future<({String peerEpk, String roomId})?> resolve(
    Map<String, dynamic> payload,
  ) async {
    final generation = ++_generation;
    if (!{'session_finished', 'ui_prompt'}.contains(payload['kind'])) {
      return null;
    }
    final machine = payload['machine_id'];
    final room = payload['room_id'];
    if (machine is! String ||
        !RegExp(r'^[A-Za-z0-9+/_=-]{43,88}$').hasMatch(machine) ||
        room is! String ||
        room.isEmpty ||
        room.length > 256 ||
        room == 'perch-control') {
      return null;
    }
    final peers = await _storage.listPeers();
    final peer = peers
        .where((p) => toStandardB64(p.remoteEpk) == toStandardB64(machine))
        .firstOrNull;
    if (peer == null || generation != _generation) return null;
    try {
      await _conn.switchTo(peer);
      if (generation != _generation) return null;
      final rooms = await _conn.refreshRoomsForPeer(peer.remoteEpk);
      if (generation != _generation ||
          rooms == null ||
          _conn.status is! StatusOnline ||
          _conn.activePeer?.remoteEpk != peer.remoteEpk ||
          !rooms.any((r) => r.roomId == room) ||
          !_conn.isRoomLive(peer.remoteEpk, room) ||
          !(await _storage.listPeers()).any(
            (p) => p.remoteEpk == peer.remoteEpk,
          )) {
        return null;
      }
      return (peerEpk: peer.remoteEpk, roomId: room);
    } on Exception {
      return null;
    }
  }
}
