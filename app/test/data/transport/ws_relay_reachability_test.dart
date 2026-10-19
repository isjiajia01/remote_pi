import 'dart:io';

import 'package:app/data/transport/ws_relay_reachability.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opens a WebSocket and closes the probe without sending peer identity',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var messages = 0;
      final closed = server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final _ in socket) {
          messages++;
        }
      });
      final result = await WsRelayReachability().check(
        'http://127.0.0.1:${server.port}',
      );
      expect(result.failure, isNull);
      expect(result.elapsed, isNotNull);
      await closed;
      expect(messages, 0);
    },
  );

  test('a refused WebSocket upgrade returns unreachable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final result = await WsRelayReachability().check('http://127.0.0.1:$port');
    expect(result.failure, RelayCheckFailure.unreachable);
    expect(result.elapsed, isNull);
  });
}
