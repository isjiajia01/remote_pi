import 'dart:async';

import 'package:app/data/push/push_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('test/perch-push-lifecycle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void scenario(void Function(FakeAsync, PushChannel, PushService) check) {
    fakeAsync((clock) {
      messenger.setMockMethodCallHandler(
        native,
        (call) async => call.method == 'requestPermission' ? true : null,
      );
      final channel = PushChannel();
      final conn = ConnectionManager(
        factory: (_, _) async => channel,
        storage: PushStorage(),
        emitDebounce: Duration.zero,
      );
      final service = PushService(conn, () => 'paired-owner', channel: native);
      conn.adopt(
        channel,
        const PeerRecord(
          remoteEpk: 'mac',
          sessionName: 'Mac',
          relayUrl: 'http://localhost',
          pairedAt: '2026-01-01',
          roomId: 'old-room',
        ),
      );
      clock.flushMicrotasks();
      channel.controls.add(
        RoomsSnapshot(
          peer: 'mac',
          rooms: [RoomInfo(startedAt: 0, roomId: 'old-room', name: 'Old Pi')],
        ),
      );
      clock.elapse(Duration.zero);
      unawaited(service.start());
      clock.flushMicrotasks();
      messenger.handlePlatformMessage(
        native.name,
        native.codec.encodeMethodCall(MethodCall('token', 'a' * 64)),
        (_) {},
      );
      clock.flushMicrotasks();
      expect(channel.sent.single.room, 'old-room');
      expect(service.status.value, 'Registering…');
      try {
        check(clock, channel, service);
      } finally {
        service.dispose();
        conn.dispose();
        clock.flushMicrotasks();
        messenger.setMockMethodCallHandler(native, null);
      }
    });
  }

  test('a silent old room cannot hide a newly online push-capable room', () {
    scenario((clock, channel, service) {
      // Real installations keep older Pi processes online alongside the new
      // extension. The active room remains old even after a new one announces.
      channel.controls.add(
        RoomsSnapshot(
          peer: 'mac',
          rooms: [
            RoomInfo(startedAt: 0, roomId: 'old-room', name: 'Old Pi'),
            RoomInfo(startedAt: 1, roomId: 'new-room', name: 'New Pi'),
          ],
        ),
      );
      clock.elapse(const Duration(seconds: 20));
      expect(channel.sent.last.room, 'new-room');
      final registration = channel.sent.last.message as PerchPushRegister;
      // A late success for the abandoned room cannot settle the current request.
      channel.messages.add(
        PerchPushResult(
          id: (channel.sent.first.message as PerchPushRegister).id,
          registered: true,
        ),
      );
      clock.flushMicrotasks();
      expect(service.status.value, 'Registering…');
      channel.rooms['new-room']!.add(
        PerchPushResult(id: registration.id, registered: true),
      );
      clock.flushMicrotasks();
      expect(service.status.value, 'Registered');
    });
  });

  test(
    'unsupported from an older minimal room immediately tries another room',
    () {
      scenario((clock, channel, service) {
        channel.controls.add(
          RoomsSnapshot(
            peer: 'mac',
            rooms: [
              RoomInfo(startedAt: 0, roomId: 'old-room', name: 'Old Pi'),
              RoomInfo(startedAt: 1, roomId: 'new-room', name: 'New Pi'),
            ],
          ),
        );
        clock.elapse(Duration.zero);
        final first = channel.sent.single.message as PerchPushRegister;
        channel.rooms['old-room']!.add(
          PerchError(
            id: first.id,
            code: 'unsupported',
            message: 'Minimal mode',
          ),
        );
        clock.flushMicrotasks();
        expect(channel.sent.length, 2);
        expect(channel.sent.last.room, 'new-room');
        final second = channel.sent.last.message as PerchPushRegister;
        channel.rooms['new-room']!.add(
          PerchPushResult(id: second.id, registered: true),
        );
        clock.flushMicrotasks();
        expect(service.status.value, 'Registered');
        // An announcement from the old room cannot replace the successful
        // machine-wide registration or cause a fresh token upload there.
        channel.controls.add(
          RoomsSnapshot(
            peer: 'mac',
            rooms: [
              RoomInfo(
                startedAt: 0,
                roomId: 'old-room',
                name: 'Old Pi',
                working: true,
              ),
              RoomInfo(startedAt: 1, roomId: 'new-room', name: 'New Pi'),
            ],
          ),
        );
        clock.elapse(const Duration(seconds: 30));
        expect(
          channel.sent
              .where((entry) => entry.message is PerchPushRegister)
              .length,
          2,
        );
        expect(service.status.value, 'Registered');
      });
    },
  );

  test('room metadata updates do not restart an exhausted registration', () {
    scenario((clock, channel, service) {
      clock.elapse(const Duration(seconds: 20));
      expect(channel.sent.length, 2);
      expect(service.status.value, contains('timed out'));
      for (var i = 0; i < 4; i++) {
        channel.controls.add(
          RoomsSnapshot(
            peer: 'mac',
            rooms: [
              RoomInfo(
                startedAt: 0,
                roomId: 'old-room',
                name: 'Old Pi',
                working: i.isEven,
              ),
            ],
          ),
        );
        clock.elapse(const Duration(seconds: 1));
      }
      expect(channel.sent.length, 2);
      expect(service.status.value, contains('timed out'));
      unawaited(service.retry());
      clock.flushMicrotasks();
      expect(channel.sent.length, 3);
      expect(service.status.value, 'Registering…');
    });
  });
}
