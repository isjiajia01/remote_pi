import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/approvals/approval_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class Channel implements IChannel, IRoomChannel {
  final messages = StreamController<ServerMessage>.broadcast();
  final sent = <({String room, ClientMessage message})>[];
  final rooms = <String, StreamController<ServerMessage>>{};
  @override
  Stream<ServerMessage> get serverMessages => messages.stream;
  @override
  Stream<ServerMessage> messagesForRoom(String room) => rooms
      .putIfAbsent(room, () => StreamController<ServerMessage>.broadcast())
      .stream;
  @override
  Future<void> sendToRoom(String room, ClientMessage message) async {
    sent.add((room: room, message: message));
  }

  @override
  Future<void> send(ClientMessage message) => sendToRoom('active', message);
  @override
  Future<void> close() async {
    await messages.close();
    for (final c in rooms.values) {
      await c.close();
    }
  }
}

class Storage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => [];
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Channel channel;
  late ConnectionManager conn;
  late ApprovalService service;
  late String owner;
  late Map<String, dynamic> fixture;
  setUp(() async {
    owner = 'paired-owner';
    fixture =
        (jsonDecode(
                  File(
                    '../.orchestration/contracts/perch-v1/tool-approval.json',
                  ).readAsStringSync(),
                )
                as Map)['request']
            as Map<String, dynamic>;
    channel = Channel();
    conn = ConnectionManager(
      factory: (_, _) async => channel,
      storage: Storage(),
    );
    service = ApprovalService(conn, () => owner);
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
  });
  Future<void> emit([Map<String, dynamic> patch = const {}]) async {
    channel.rooms['main']!.add(
      PerchToolApprovalRequest.fromJson({
        ...fixture,
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        ...patch,
      }),
    );
    await flush();
  }

  test(
    'verified approval routes and sends exact binding to origin room after room switch',
    () async {
      await emit();
      final approval = service.approvalsFor('mac', 'main').single;
      final payload = {
        'kind': 'approval_request',
        'event_id': approval.request.id,
        'session_id': approval.request.sessionId,
        'tool_call_id': approval.request.toolCallId,
      };
      expect(service.resolveNotification(payload), same(approval));
      expect(
        service.resolveNotification({...payload, 'session_id': 'other'}),
        isNull,
      );
      expect(
        service.resolveNotification({...payload, 'tool_call_id': 'other'}),
        isNull,
      );
      conn.switchRoom('other');
      await service.decide(approval, PerchApprovalDecision.allow);
      expect(channel.sent.single.room, 'main');
      final decision = channel.sent.single.message.toJson();
      expect(decision['owner'], owner);
      expect(decision['session_id'], approval.request.sessionId);
      expect(decision['tool_call_id'], approval.request.toolCallId);
      expect(decision['args_digest'], approval.request.argsDigest);
      expect(service.approvalsFor('mac', 'main'), isEmpty);
      await expectLater(
        service.decide(approval, PerchApprovalDecision.allow),
        throwsStateError,
      );
    },
  );
  test(
    'foreign owner, tampered arguments and expired requests never surface',
    () async {
      await emit({'owner': 'other'});
      await emit({
        'args': {'different': true},
      });
      await emit({'expires_at': DateTime.now().millisecondsSinceEpoch});
      expect(service.approvalsFor('mac', 'main'), isEmpty);
    },
  );
  test(
    'owner replacement and transport replacement cannot release a stale challenge',
    () async {
      await emit();
      final approval = service.approvalsFor('mac', 'main').single;
      owner = 'replacement';
      await expectLater(
        service.decide(approval, PerchApprovalDecision.allow),
        throwsStateError,
      );
      owner = 'paired-owner';
      conn.adopt(
        Channel(),
        const PeerRecord(
          remoteEpk: 'other',
          sessionName: 'Other',
          relayUrl: 'http://localhost',
          pairedAt: '2026-01-01',
        ),
      );
      await flush();
      await expectLater(
        service.decide(approval, PerchApprovalDecision.allow),
        throwsStateError,
      );
      expect(channel.sent, isEmpty);
    },
  );
  test('expiry after receipt blocks decision', () async {
    await emit({
      'expires_at': DateTime.now()
          .add(const Duration(milliseconds: 50))
          .millisecondsSinceEpoch,
    });
    final approval = service.approvalsFor('mac', 'main').single;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await expectLater(
      service.decide(approval, PerchApprovalDecision.deny),
      throwsStateError,
    );
    expect(channel.sent, isEmpty);
  });
}
