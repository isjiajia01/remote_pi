import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/services.dart';

/// Minimal iOS bridge. Native code queues cold-launch taps until Dart is ready.
class PushService extends Service {
  PushService(this._conn, this._owner, {MethodChannel? channel})
    : _native = channel ?? const MethodChannel('dev.zhangjiajia.perch/push') {
    _native.setMethodCallHandler(_onNative);
    _statusSub = _conn.statusStream.listen(_bind);
    _bind(_conn.status);
  }
  final ConnectionManager _conn;
  final String? Function() _owner;
  final MethodChannel _native;
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<ConnectionStatus>? _statusSub;
  String? _token;
  bool _enabled = false;
  IChannel? _registeredChannel;
  String? _registeredToken;
  String? _registeredOwner;
  String? _pendingId;
  Timer? _pendingTimer;
  StreamSubscription<ServerMessage>? _messagesSub;

  void _bind(ConnectionStatus status) {
    _messagesSub?.cancel();
    _pendingTimer?.cancel();
    _pendingId = null;
    _registeredChannel = null;
    if (status is StatusOnline) {
      _messagesSub = status.channel.serverMessages.listen((message) {
        if (message is PerchPushResult && message.id == _pendingId) {
          _pendingTimer?.cancel();
          _pendingId = null;
          if (message.registered) {
            _registeredChannel = status.channel;
          }
        } else if (message is PerchError && message.id == _pendingId) {
          _pendingTimer?.cancel();
          _pendingId = null;
        }
      }, onError: (Object _, StackTrace _) {});
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
      if (!allowed) await unregister();
      if (allowed) await _upload();
    } on MissingPluginException {
      // Other platforms retain their existing behavior.
    } on PlatformException {
      // Permission/registration failure is optional and must not block boot.
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
    if (_pendingId != null) return;
    if (identical(_registeredChannel, status.channel) &&
        _registeredToken == token &&
        _registeredOwner == owner) {
      return;
    }
    final id = uuid7();
    _pendingId = id;
    _registeredToken = token;
    _registeredOwner = owner;
    _pendingTimer = Timer(const Duration(seconds: 10), () {
      _pendingId = null;
    });
    try {
      await status.channel.send(
        PerchPushRegister(
          id: id,
          owner: owner,
          token: token,
          environment: PerchPushEnvironment.sandbox,
        ),
      );
    } on Exception {
      if (_pendingId == id) {
        _pendingId = null;
        _pendingTimer?.cancel();
      }
      /* Retry on the next connection/foreground event. */
    }
  }

  Future<void> unregister() async {
    final status = _conn.status;
    final owner = _owner();
    final token = _token;
    _pendingTimer?.cancel();
    _pendingId = null;
    _registeredChannel = null;
    _registeredToken = null;
    _registeredOwner = null;
    if (status is! StatusOnline || owner == null || token == null) return;
    try {
      await status.channel.send(
        PerchPushRegister(
          id: uuid7(),
          owner: owner,
          token: token,
          environment: PerchPushEnvironment.sandbox,
          unregister: true,
        ),
      );
    } on Exception {
      /* Best effort when the peer is offline. */
    }
  }

  @override
  void dispose() {
    _native.setMethodCallHandler(null);
    _statusSub?.cancel();
    _messagesSub?.cancel();
    _pendingTimer?.cancel();
    _taps.close();
    super.dispose();
  }
}
