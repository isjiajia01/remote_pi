import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/control_client.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';

class ControlRepository extends ControlClient {
  ControlRepository(this._conn, {this.timeoutOverride}) {
    _statusSub = _conn.statusStream.listen((_) => _bind());
    _bind();
  }
  static const room = 'perch-control';
  final ConnectionManager _conn;
  final Duration? timeoutOverride;
  final _connections = StreamController<void>.broadcast();
  final _pending = <String, _PendingControl>{};
  late final StreamSubscription<ConnectionStatus> _statusSub;
  StreamSubscription<ServerMessage>? _messagesSub;
  IChannel? _channel;
  ControlCapabilities? _capabilities;
  int _generation = 0;

  @override
  String get connectionKey =>
      '${_conn.activePeer?.remoteEpk ?? ''}|$_generation';
  @override
  String get machineLabel =>
      _conn.activePeer?.nickname ?? _conn.activePeer?.sessionName ?? 'Mac';
  @override
  Stream<void> get connections => _connections.stream;

  void _bind() {
    final channel = _conn.channel;
    if (identical(_channel, channel)) return;
    _generation++;
    _messagesSub?.cancel();
    _failPending();
    _channel = channel;
    _capabilities = null;
    if (channel is IRoomChannel) {
      _messagesSub = (channel as IRoomChannel)
          .messagesForRoom(room)
          .listen(
            _receive,
            onError: (Object _, StackTrace _) => _failPending(),
            onDone: _failPending,
          );
    }
    _connections.add(null);
  }

  void _failPending() {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final item in pending) {
      item.timer.cancel();
      item.completer.completeError(
        const ControlFailure('offline', 'Result unknown, refresh'),
      );
    }
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
    if (message is PerchResult &&
        (message.method != pending.method ||
            message.result['scope'] != 'supervisor')) {
      return;
    }
    if (message is PerchCapabilitiesResult && pending.method != null) return;
    if (message is PerchResult && pending.method == null) return;
    _pending.remove(id);
    pending.timer.cancel();
    if (message is PerchError) {
      pending.completer.completeError(
        ControlFailure(message.code, message.message),
      );
    } else {
      pending.completer.complete(message);
    }
  }

  Future<ServerMessage> _request(
    ClientMessage message,
    String id,
    String? method,
  ) {
    final channel = _channel;
    if (channel is! IRoomChannel) {
      return Future.error(
        const ControlFailure('offline', 'Result unknown, refresh'),
      );
    }
    final completer = Completer<ServerMessage>();
    // Individual deadlines include supervisor snapshot and mutation IPC calls.
    final seconds = switch (method) {
      null => 4,
      'daemon.restart' => 25,
      'daemon.start' || 'daemon.stop' || 'cron.run' => 20,
      _ => 15,
    };
    final timer = Timer(timeoutOverride ?? Duration(seconds: seconds), () {
      _pending
          .remove(id)
          ?.completer
          .completeError(
            const ControlFailure('timeout', 'Result unknown, refresh'),
          );
    });
    _pending[id] = _PendingControl(completer, timer, method);
    unawaited(
      (channel as IRoomChannel).sendToRoom(room, message).catchError((
        Object _,
        StackTrace _,
      ) {
        final item = _pending.remove(id);
        item?.timer.cancel();
        item?.completer.completeError(
          const ControlFailure('offline', 'Result unknown, refresh'),
        );
      }),
    );
    return completer.future;
  }

  @override
  Future<ControlCapabilities> capabilities() async {
    final generation = _generation;
    final id = 'control_${uuid7()}';
    final response =
        await _request(PerchCapabilitiesGet(id: id), id, null)
            as PerchCapabilitiesResult;
    if (generation != _generation) {
      throw const ControlFailure('offline', 'Connection changed');
    }
    if (response.scope != 'supervisor' || response.methods.isEmpty) {
      throw const ControlFailure(
        'unsupported',
        'Remote control not enabled on this Mac',
      );
    }
    return _capabilities = ControlCapabilities(
      response.methods,
      maxPromptChars: (response.limits['max_prompt_chars'] ?? 8192).clamp(
        1,
        8192,
      ),
    );
  }

  @override
  ControlAction action(
    String method,
    Map<String, dynamic> params,
    int? revision,
  ) => ControlAction('control_${uuid7()}', method, params, revision);

  @override
  Future<ControlReply> execute(ControlAction action) async {
    if (_capabilities?.methods.contains(action.method) != true) {
      throw const ControlFailure(
        'unsupported',
        'Remote control not enabled on this Mac',
      );
    }
    final response =
        await _request(
              PerchRequest(
                id: action.id,
                method: action.method,
                params: action.params,
                expectedRevision: action.revision,
              ),
              action.id,
              action.method,
            )
            as PerchResult;
    return response.control;
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _messagesSub?.cancel();
    _failPending();
    _connections.close();
    super.dispose();
  }
}

class _PendingControl {
  const _PendingControl(this.completer, this.timer, this.method);
  final Completer<ServerMessage> completer;
  final Timer timer;
  final String? method;
}
