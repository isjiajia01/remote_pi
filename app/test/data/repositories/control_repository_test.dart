import 'dart:async';

import 'package:app/data/repositories/control_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _Channel extends Fake implements IChannel, IRoomChannel {
  final replies = StreamController<ServerMessage>.broadcast();
  int negotiations = 0;
  @override
  Stream<ServerMessage> messagesForRoom(String room) => replies.stream;
  @override
  Future<void> sendToRoom(String room, ClientMessage message) async {
    if (message is PerchCapabilitiesGet) {
      negotiations++;
      replies.add(
        PerchCapabilitiesResult(
          id: message.id,
          methods: ['directories.list'],
          ackSemantics: 'delivery_only',
          limits: {},
          scope: 'supervisor',
        ),
      );
    }
  }
}

class _Connection extends Fake implements ConnectionManager {
  _Connection(this.current);
  IChannel? current;
  final changes = StreamController<ConnectionStatus>.broadcast();
  @override
  IChannel? get channel => current;
  @override
  PeerRecord? get activePeer => null;
  @override
  Stream<ConnectionStatus> get statusStream => changes.stream;
}

void main() {
  test(
    'capabilities cached for connection and invalidated on disconnect/reconnect',
    () async {
      final first = _Channel();
      final second = _Channel();
      final connection = _Connection(first);
      final repository = ControlRepository(connection, cacheCapabilities: true);
      addTearDown(() async {
        repository.dispose();
        await connection.changes.close();
        await first.replies.close();
        await second.replies.close();
      });
      final a = await repository.capabilities();
      final b = await repository.capabilities();
      expect(identical(a, b), isTrue);
      expect(first.negotiations, 1);
      connection.current = null;
      connection.changes.add(const StatusConnecting());
      await Future<void>.delayed(Duration.zero);
      connection.current = second;
      connection.changes.add(StatusOnline(second));
      await Future<void>.delayed(Duration.zero);
      await repository.capabilities();
      expect(second.negotiations, 1);
      expect(first.negotiations, 1);
    },
  );
}
