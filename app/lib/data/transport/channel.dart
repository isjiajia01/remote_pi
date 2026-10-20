import 'dart:typed_data';

import 'package:app/protocol/protocol.dart';

/// Abstract channel — testable interface over [PlainPeerChannel].
abstract class IChannel {
  Stream<ServerMessage> get serverMessages;
  Future<void> send(ClientMessage msg);
  Future<void> close();
}

/// Optional capability mixed into a channel that also speaks raw relay
/// control frames (subscribe_presence, peer_online, etc — see plano 12).
/// ConnectionManager does an `is IControlLink` cast to drive presence;
/// channels that don't implement it simply skip the subsystem.
abstract class IControlLink {
  Stream<ControlInbound> get controlFrames;
  void sendControl(Map<String, dynamic> json);
}

/// Additional room traffic shares authentication without changing the chat room.
abstract interface class IRoomChannel {
  Stream<ServerMessage> messagesForRoom(String room);
  Future<void> sendToRoom(String room, ClientMessage message);
}

abstract interface class IRoomTransport {
  Stream<({String room, Uint8List bytes})> get roomMessages;
  Future<void> sendToRoom(String room, Uint8List bytes);
}
