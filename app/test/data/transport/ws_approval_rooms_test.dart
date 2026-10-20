import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/transport/ws_transport.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'room stream retains source room and peer while legacy chat remains isolated',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final ready = Completer<WebSocket>();
      final receivedAuth = Completer<void>();
      unawaited(() async {
        final socket = await WebSocketTransformer.upgrade(await server.first);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map;
          if (message['type'] == 'hello') {
            socket.add(
              jsonEncode({
                'type': 'challenge',
                'nonce': base64Encode(List.filled(32, 1)),
              }),
            );
          } else if (message['type'] == 'auth') {
            receivedAuth.complete();
          }
        });
        ready.complete(socket);
      }());
      final peer = base64Encode(List.filled(32, 2));
      final transport = await WsTransport.connect(
        relayUrl: 'http://127.0.0.1:${server.port}',
        peerPubkey: peer,
        ed25519Key: await Ed25519().newKeyPair(),
      );
      addTearDown(transport.close);
      final socket = await ready.future;
      addTearDown(() => socket.close());
      await receivedAuth.future;
      transport.setActiveRoom('chat');
      final frames = <({String room, List<int> bytes})>[];
      final sub = transport.roomMessages.listen(
        (frame) => frames.add((room: frame.room, bytes: frame.bytes)),
      );
      addTearDown(sub.cancel);
      void send(String sourcePeer, String room, String text) => socket.add(
        jsonEncode({
          'peer': sourcePeer,
          'room': room,
          'ct': base64Encode(utf8.encode(text)),
        }),
      );
      send(base64Encode(List.filled(32, 3)), 'other', 'wrong-peer');
      send(peer, 'other', 'approval');
      send(peer, 'chat', 'chat-message');
      expect(
        utf8.decode(
          await transport.receive().timeout(const Duration(seconds: 2)),
        ),
        'chat-message',
      );
      expect(frames.map((frame) => frame.room), ['other', 'chat']);
      expect(utf8.decode(frames.first.bytes), 'approval');
    },
  );
}
