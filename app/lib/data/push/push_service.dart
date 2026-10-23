import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Minimal iOS bridge. Native code queues cold-launch taps until Dart is ready.
class PushService extends Service {
  PushService(this._conn, this._owner, {MethodChannel? channel})
    : _native = channel ?? const MethodChannel('dev.zhangjiajia.perch/push') {
    _native.setMethodCallHandler(_onNative);
    _statusSub = _conn.statusStream.listen(_bind);
    _roomsSub = _conn.roomsStream.listen((_) => unawaited(_upload()));
    _bind(_conn.status);
  }
  final ConnectionManager _conn;
  final String? Function() _owner;
  final MethodChannel _native;
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<ConnectionStatus>? _statusSub;
  final status = ValueNotifier<String>('Waiting to connect');
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  String? _registeredRoom;
  String? _pendingRoom;
  int _timeoutRetries = 0;
  void Function(ServerMessage)? _onMessage;
  String? _listeningRoom;
  String? _token;
  bool _enabled = false;
  IChannel? _registeredChannel;
  String? _registeredToken;
  String? _registeredOwner;
  String? _pendingId;
  Timer? _pendingTimer;
  StreamSubscription<ServerMessage>? _messagesSub;
  StreamSubscription<ServerMessage>? _roomMessagesSub;

  void _bind(ConnectionStatus status) {
    _messagesSub?.cancel();
    _roomMessagesSub?.cancel();
    _pendingTimer?.cancel();
    _pendingId = null;
    _registeredChannel = null;
    _listeningRoom = null;
    _timeoutRetries = 0;
    this.status.value = _enabled ? 'Waiting to connect' : this.status.value;
    if (status is StatusOnline) {
      void onMessage(ServerMessage message) {
        if (message is PerchPushResult && message.id == _pendingId) {
          _pendingTimer?.cancel();
          _pendingId = null;
          if (message.registered) {
            _registeredChannel = status.channel;
            _registeredRoom = _pendingRoom;
            this.status.value = 'Registered';
          } else {
            this.status.value = 'Configuration unavailable';
          }
        } else if (message is PerchError && message.id == _pendingId) {
          _pendingTimer?.cancel();
          _pendingId = null;
          this.status.value = 'Configuration unavailable';
        }
      }

      _messagesSub = status.channel.serverMessages.listen(
        onMessage,
        onError: (Object _, StackTrace _) {},
      );
      _onMessage = onMessage;
    }
    unawaited(_upload());
  }

  Stream<Map<String, dynamic>> get taps => _taps.stream;

  Future<void> start() async {
    try {
      await _native.invokeMethod<void>('ready');
      final allowed =
          await _native.invokeMethod<bool>('requestPermission') ?? false;
      _enabled = allowed;
      if (!allowed) {
        status.value =
            'Permission denied — enable notifications in iOS Settings';
      }
      if (!allowed) await unregister();
      if (allowed) await _upload();
    } on MissingPluginException {
      // Other platforms retain their existing behavior.
    } on PlatformException {
      status.value = 'Registration failed — tap to retry';
    }
  }

  Future<void> _onNative(MethodCall call) async {
    if (call.method == 'token' && call.arguments is String) {
      final token = call.arguments as String;
      if (!RegExp(r'^[a-fA-F0-9]{64,512}$').hasMatch(token) ||
          token.length.isOdd) {
        return;
      }
      final previous = _token;
      if (previous != null && previous != token) await unregister();
      _token = token.toLowerCase();
      await _upload();
    } else if (call.method == 'registrationFailed') {
      status.value = 'Registration failed — tap to retry';
    } else if (call.method == 'tap' && call.arguments is Map) {
      _taps.add(Map<String, dynamic>.from(call.arguments as Map));
    }
  }

  Future<void> _upload() async {
    final status = _conn.status;
    final owner = _owner();
    final token = _token;
    if (!_enabled ||
        owner == null ||
        token == null ||
        status is! StatusOnline) {
      return;
    }
    final peer = _conn.activePeer;
    final rooms = peer == null
        ? <RoomInfo>[]
        : _conn
              .roomsFor(peer.remoteEpk)
              .where((room) => _conn.isRoomLive(peer.remoteEpk, room.roomId))
              .toList();
    if (rooms.isEmpty) {
      this.status.value = 'Open a running session to enable notifications';
      return;
    }
    final room =
        rooms.where((r) => r.roomId == _conn.activeRoomId).firstOrNull ??
        rooms.first;
    if (_pendingId != null && _pendingRoom == room.roomId) return;
    if (_pendingId != null) {
      _pendingTimer?.cancel();
      _pendingId = null;
    }
    if (identical(_registeredChannel, status.channel) &&
        _registeredToken == token &&
        _registeredOwner == owner &&
        _registeredRoom == room.roomId) {
      return;
    }
    if (status.channel is IRoomChannel && _listeningRoom != room.roomId) {
      unawaited(_roomMessagesSub?.cancel());
      _listeningRoom = room.roomId;
      _roomMessagesSub = (status.channel as IRoomChannel)
          .messagesForRoom(room.roomId)
          .listen(
            (message) => _onMessage?.call(message),
            onError: (Object _, StackTrace _) {},
          );
    }
    final id = uuid7();
    _pendingId = id;
    _pendingRoom = room.roomId;
    this.status.value = 'Registering…';
    _registeredToken = token;
    _registeredOwner = owner;
    _pendingTimer = Timer(const Duration(seconds: 10), () {
      _pendingId = null;
      this.status.value = 'Registration timed out — tap to retry';
      if (_timeoutRetries++ < 1) unawaited(_upload());
    });
    try {
      final message = PerchPushRegister(
        id: id,
        owner: owner,
        token: token,
        environment: PerchPushEnvironment.sandbox,
      );
      final channel = status.channel;
      if (channel is IRoomChannel) {
        await (channel as IRoomChannel).sendToRoom(room.roomId, message);
      } else {
        if (_conn.activeRoomId != room.roomId) {
          this.status.value = 'Open a running session to enable notifications';
          _pendingTimer?.cancel();
          _pendingId = null;
          return;
        }
        await channel.send(message);
      }
    } on Exception {
      if (_pendingId == id) {
        _pendingId = null;
        _pendingTimer?.cancel();
      }
      this.status.value = 'Registration failed — tap to retry';
    }
  }

  Future<void> retry() async {
    _pendingTimer?.cancel();
    _pendingId = null;
    _registeredChannel = null;
    _timeoutRetries = 0;
    await start();
  }

  Future<void> unregister() async {
    final status = _conn.status;
    final owner = _owner();
    final token = _token;
    _pendingTimer?.cancel();
    _pendingId = null;
    final room = _registeredRoom ?? _pendingRoom;
    _registeredChannel = null;
    _registeredToken = null;
    _registeredRoom = null;
    _registeredOwner = null;
    if (status is! StatusOnline || owner == null || token == null) return;
    try {
      final message = PerchPushRegister(
        id: uuid7(),
        owner: owner,
        token: token,
        environment: PerchPushEnvironment.sandbox,
        unregister: true,
      );
      final channel = status.channel;
      if (channel is IRoomChannel && room != null) {
        await (channel as IRoomChannel).sendToRoom(room, message);
      } else {
        await channel.send(message);
      }
    } on Exception {
      /* Best effort when the peer is offline. */
    }
  }

  @override
  void dispose() {
    _native.setMethodCallHandler(null);
    _statusSub?.cancel();
    _roomsSub?.cancel();
    status.dispose();
    _messagesSub?.cancel();
    _roomMessagesSub?.cancel();
    _pendingTimer?.cancel();
    _taps.close();
    super.dispose();
  }
}
