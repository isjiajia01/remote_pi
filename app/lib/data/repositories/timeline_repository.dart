import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/timeline_reader.dart';
import 'package:app/domain/entities/agent_timeline.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';

class TimelineRepository extends TimelineReader {
  TimelineRepository(
    this._conn,
    this._storage, {
    Duration capabilityTimeout = const Duration(seconds: 4),
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _capabilityTimeout = capabilityTimeout,
       _requestTimeout = requestTimeout {
    _statusSub = _conn.statusStream.listen((_) => _bind());
    _roomsSub = _conn.roomsStream.listen((_) => _bind());
    _bind();
  }
  final ConnectionManager _conn;
  final PairingStorage _storage;
  final Duration _capabilityTimeout;
  final Duration _requestTimeout;
  final _connections = StreamController<TimelineConnection>.broadcast();
  final _pending = <String, _PendingRead>{};
  final _supportedKeys = <String>{};
  late final StreamSubscription<ConnectionStatus> _statusSub;
  late final StreamSubscription<Map<String, List<RoomInfo>>> _roomsSub;
  StreamSubscription<ServerMessage>? _messagesSub;
  IChannel? _channel;
  String? _boundKey;

  @override
  TimelineConnection get connection => TimelineConnection(
    key: '${_conn.activePeer?.remoteEpk ?? ''}|${_conn.activeRoomId}',
    machineId: _conn.activePeer?.remoteEpk,
    label:
        _conn.activePeer?.nickname ??
        _conn.activePeer?.sessionName ??
        'Local broker',
    online: _conn.channel != null,
  );
  @override
  Stream<TimelineConnection> get connections => _connections.stream;

  void _bind() {
    final next = connection;
    final channel = _conn.channel;
    if (identical(channel, _channel) && next.key == _boundKey) return;
    _messagesSub?.cancel();
    _failPending(const PerchReadFailure('offline', 'Connection changed'));
    _channel = channel;
    _boundKey = next.key;
    _messagesSub = channel?.serverMessages.listen(
      _receive,
      onError: (Object _, StackTrace _) =>
          _failPending(const PerchReadFailure('offline', 'Transport failed')),
      onDone: () =>
          _failPending(const PerchReadFailure('offline', 'Connection closed')),
    );
    _connections.add(next);
  }

  void _receive(ServerMessage message) {
    final id = switch (message) {
      PerchCapabilitiesResult(:final id) => id,
      PerchResult(:final id) => id,
      PerchError(:final id) => id,
      _ => null,
    };
    final pending = _pending[id];
    if (pending == null) return;
    if (message is PerchResult && message.method != pending.method) return;
    if (message is PerchCapabilitiesResult && pending.method != null) return;
    if (message is PerchResult && pending.method == null) return;
    _pending.remove(id);
    pending.timer.cancel();
    if (message is PerchError) {
      pending.completer.completeError(
        PerchReadFailure(message.code, message.message),
      );
    } else {
      pending.completer.complete(message);
    }
  }

  void _failPending(PerchReadFailure error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final item in pending) {
      item.timer.cancel();
      item.completer.completeError(error);
    }
  }

  Future<ServerMessage> _request(
    ClientMessage message,
    String id, {
    String? method,
    required Duration timeout,
  }) async {
    final channel = _channel;
    if (channel == null) throw const PerchReadFailure('offline', 'Pi offline');
    final completer = Completer<ServerMessage>();
    final timer = Timer(timeout, () {
      final item = _pending.remove(id);
      item?.completer.completeError(
        const PerchReadFailure('timeout', 'Read timed out'),
      );
    });
    _pending[id] = _PendingRead(completer, timer, method);
    // Listen for send failures immediately; the response timeout also bounds send.
    unawaited(
      channel.send(message).catchError((Object error, StackTrace stack) {
        final item = _pending.remove(id);
        item?.timer.cancel();
        item?.completer.completeError(
          const PerchReadFailure('offline', 'Unable to read from Pi'),
          stack,
        );
      }),
    );
    return completer.future;
  }

  @override
  Future<bool> isSupported() async {
    final id = 'perch_${uuid7()}';
    final key = connection.key;
    try {
      final result = await _request(
        PerchCapabilitiesGet(id: id),
        id,
        timeout: _capabilityTimeout,
      );
      final supported = (result as PerchCapabilitiesResult).supportsTimeline;
      if (supported) {
        _supportedKeys.add(key);
      } else {
        _supportedKeys.remove(key);
      }
      return supported;
    } on PerchReadFailure catch (error) {
      if (error.code == 'unsupported') {
        _supportedKeys.remove(key);
        return false;
      }
      if (error.code == 'timeout' && !_supportedKeys.contains(key)) {
        return false;
      }
      rethrow;
    }
  }

  Future<PerchResult> _read(String method, Map<String, dynamic> params) async {
    final id = 'perch_${uuid7()}';
    return await _request(
          PerchRequest(id: id, method: method, params: params),
          id,
          method: method,
          timeout: _requestTimeout,
        )
        as PerchResult;
  }

  @override
  Future<AgentSnapshot> snapshot() async =>
      (await _read('agents.list', {})).snapshot;
  @override
  Future<AgentEventPage> events({
    required String epoch,
    required int cursor,
    int waitMs = 25000,
  }) async => (await _read('agents.events', {
    'epoch': epoch,
    'cursor': cursor,
    'limit': 128,
    'wait_ms': waitMs.clamp(0, 25000),
  })).eventPage;

  @override
  Future<List<TimelineMachine>> machines() async => [
    for (final peer in await _storage.listPeers())
      TimelineMachine(peer.remoteEpk, peer.nickname ?? peer.sessionName),
  ];

  @override
  Future<void> selectMachine(String id) async {
    if (id == _conn.activePeer?.remoteEpk) return;
    final peers = await _storage.listPeers();
    final peer = peers.where((p) => p.remoteEpk == id).firstOrNull;
    if (peer != null) await _conn.switchTo(peer);
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _roomsSub.cancel();
    _messagesSub?.cancel();
    _failPending(const PerchReadFailure('offline', 'Timeline closed'));
    _connections.close();
    super.dispose();
  }
}

class _PendingRead {
  const _PendingRead(this.completer, this.timer, this.method);
  final Completer<ServerMessage> completer;
  final Timer timer;
  final String? method;
}
