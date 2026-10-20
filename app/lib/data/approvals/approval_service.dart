import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/approval_client.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/protocol/approval_digest.dart';
import 'package:app/protocol/protocol.dart';

/// Ephemeral approvals retain their authenticated transport and room origin.
class ApprovalService extends Service implements ApprovalClient {
  ApprovalService(this._conn, this._owner) {
    _statusSub = _conn.statusStream.listen(_bind);
    _roomsSub = _conn.roomsStream.listen((_) => _subscribeRooms());
    _bind(_conn.status);
  }
  final ConnectionManager _conn;
  final String? Function() _owner;
  final _changes = StreamController<void>.broadcast();
  final _pending = <String, BoundApproval>{};
  final _roomSubs = <String, StreamSubscription<ServerMessage>>{};
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  IChannel? _channel;
  String? _peer;
  int _generation = 0;
  final _sending = <String>{};

  @override
  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _bind(ConnectionStatus status) {
    _generation++;
    for (final subscription in _roomSubs.values) {
      subscription.cancel();
    }
    _roomSubs.clear();
    _pending.clear();
    _channel = status is StatusOnline ? status.channel : null;
    _peer = _conn.activePeer?.remoteEpk;
    _subscribeRooms();
    _notify();
  }

  void _subscribeRooms() {
    final channel = _channel;
    final peer = _peer;
    if (channel == null || peer == null) return;
    final rooms = channel is IRoomChannel
        ? {
            'main',
            _conn.activeRoomId,
            ..._conn.roomsFor(peer).map((r) => r.roomId),
          }
        : {_conn.activeRoomId};
    for (final room in rooms) {
      if (_roomSubs.containsKey(room)) continue;
      final generation = _generation;
      final messages = channel is IRoomChannel
          ? (channel as IRoomChannel).messagesForRoom(room)
          : channel.serverMessages;
      _roomSubs[room] = messages.listen((message) {
        if (message is PerchToolApprovalRequest) {
          unawaited(_receive(message, peer, room, generation));
        }
      }, onError: (Object _, StackTrace _) {});
    }
  }

  Future<void> _receive(
    PerchToolApprovalRequest request,
    String peer,
    String room,
    int generation,
  ) async {
    if (request.owner != _owner() || request.isExpired(DateTime.now())) return;
    final digest = await approvalArgsDigest(request.args);
    if (generation != _generation ||
        request.owner != _owner() ||
        digest != request.argsDigest ||
        request.isExpired(DateTime.now())) {
      return;
    }
    _pending.removeWhere(
      (_, approval) => approval.request.isExpired(DateTime.now()),
    );
    if (_pending.length >= 32) return;
    // Never replace a challenge with a conflicting binding under the same id.
    if (_pending.containsKey(request.id)) return;
    _pending[request.id] = BoundApproval(
      request: request,
      peerEpk: peer,
      roomId: room,
    );
    _notify();
  }

  @override
  List<BoundApproval> approvalsFor(String peerEpk, String roomId) =>
      List.unmodifiable(
        _pending.values.where(
          (a) =>
              a.peerEpk == peerEpk &&
              a.roomId == roomId &&
              a.request.owner == _owner(),
        ),
      );

  @override
  BoundApproval? resolveNotification(Map<String, dynamic> payload) {
    if (payload['kind'] != 'approval_request') return null;
    final approval = _pending[payload['event_id']];
    if (approval == null ||
        approval.request.owner != _owner() ||
        approval.request.sessionId != payload['session_id'] ||
        approval.request.toolCallId != payload['tool_call_id'] ||
        approval.request.isExpired(DateTime.now())) {
      return null;
    }
    return approval;
  }

  @override
  Future<void> decide(
    BoundApproval approval,
    PerchApprovalDecision decision,
  ) async {
    final request = approval.request;
    final channel = _channel;
    if (!identical(_pending[request.id], approval) ||
        channel == null ||
        _conn.activePeer?.remoteEpk != approval.peerEpk ||
        request.owner != _owner() ||
        request.isExpired(DateTime.now()) ||
        !_sending.add(request.id)) {
      throw StateError('Approval is no longer available');
    }
    try {
      final digest = await approvalArgsDigest(request.args);
      if (!identical(channel, _channel) ||
          !identical(_pending[request.id], approval) ||
          request.owner != _owner() ||
          request.isExpired(DateTime.now()) ||
          digest != request.argsDigest) {
        throw StateError('Approval is no longer available');
      }
      final message = PerchToolApprovalDecision(
        request: request,
        decision: decision,
      );
      if (channel is IRoomChannel) {
        await (channel as IRoomChannel).sendToRoom(approval.roomId, message);
      } else {
        if (_conn.activeRoomId != approval.roomId) {
          throw StateError('Session changed');
        }
        await channel.send(message);
      }
      _pending.remove(request.id);
      _notify();
    } finally {
      _sending.remove(request.id);
    }
  }

  @override
  void dispose() {
    _generation++;
    _statusSub?.cancel();
    _roomsSub?.cancel();
    for (final subscription in _roomSubs.values) {
      subscription.cancel();
    }
    _changes.close();
    super.dispose();
  }
}
