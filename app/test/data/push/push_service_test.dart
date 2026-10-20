import 'package:app/data/push/push_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../approvals/approval_service_test.dart' show Channel, Storage, flush;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('test/perch-push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Channel channel;
  late ConnectionManager conn;
  late PushService service;
  var allowed = true;
  Future<void> emit(String method, Object? arguments) async {
    await messenger.handlePlatformMessage(
      native.name,
      native.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await flush();
  }

  setUp(() async {
    allowed = true;
    messenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'requestPermission' ? allowed : null,
    );
    channel = Channel();
    conn = ConnectionManager(
      factory: (_, _) async => channel,
      storage: Storage(),
    );
    service = PushService(conn, () => 'paired-owner', channel: native);
    conn.adopt(
      channel,
      const PeerRecord(
        remoteEpk: 'mac',
        sessionName: 'Mac',
        relayUrl: 'http://localhost',
        pairedAt: '2026-01-01',
      ),
    );
    await flush();
  });
  tearDown(() {
    service.dispose();
    conn.dispose();
    messenger.setMockMethodCallHandler(native, null);
  });
  test(
    'permission and token upload use sandbox, correlate reply, rotate and unregister',
    () async {
      await service.start();
      await emit('token', 'a' * 64);
      final registration = channel.sent.single.message as PerchPushRegister;
      expect(registration.owner, 'paired-owner');
      expect(registration.token, 'a' * 64);
      expect(registration.environment, PerchPushEnvironment.sandbox);
      channel.messages.add(
        PerchPushResult(id: registration.id, registered: true),
      );
      await flush();
      await service.start();
      expect(channel.sent.length, 1);
      await emit('token', 'b' * 64);
      final sent = channel.sent
          .map((s) => s.message)
          .whereType<PerchPushRegister>()
          .toList();
      expect(sent[1].unregister, isTrue);
      expect(sent[1].token, 'a' * 64);
      expect(sent[2].token, 'b' * 64);
      allowed = false;
      await service.start();
      expect(
        (channel.sent.last.message as PerchPushRegister).unregister,
        isTrue,
      );
      await emit('token', 'c' * 64);
      expect(
        channel.sent.length,
        5,
      ); // old token cleanup; no registration while denied
    },
  );
  test(
    'invalid token is ignored and native taps are navigation hints',
    () async {
      await service.start();
      await emit('token', 'bad');
      expect(channel.sent, isEmpty);
      final tap = service.taps.first;
      await emit('tap', {
        'kind': 'approval_request',
        'event_id': 'a',
        'session_id': 's',
        'tool_call_id': 't',
      });
      expect((await tap)['event_id'], 'a');
      expect(channel.sent, isEmpty);
    },
  );
  test('server rejection permits retry on next foreground event', () async {
    await service.start();
    await emit('token', 'a' * 64);
    final first = channel.sent.single.message as PerchPushRegister;
    channel.messages.add(
      PerchError(id: first.id, code: 'forbidden', message: 'disabled'),
    );
    await flush();
    await service.start();
    expect(channel.sent.length, 2);
  });
}
