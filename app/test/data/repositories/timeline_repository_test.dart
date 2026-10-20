import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/repositories/timeline_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/entities/agent_timeline.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _Channel implements IChannel {
  final messages = StreamController<ServerMessage>.broadcast();
  final sent = <ClientMessage>[];
  bool failSend = false;
  @override
  Stream<ServerMessage> get serverMessages => messages.stream;
  @override
  Future<void> send(ClientMessage message) async {
    if (failSend) throw StateError('send failed');
    sent.add(message);
  }

  @override
  Future<void> close() => messages.close();
  void respond(String fixture, String id, {String? method}) {
    final raw =
        (jsonDecode(
                  File(
                    '../.orchestration/contracts/perch-v1/$fixture.json',
                  ).readAsStringSync(),
                )
                as Map)['response']
            as Map<String, dynamic>;
    messages.add(ServerMessage.fromJson({...raw, 'id': id, 'method': ?method}));
  }
}

class _Storage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => [];
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Channel channel;
  late ConnectionManager conn;
  late TimelineRepository repo;
  setUp(() async {
    channel = _Channel();
    conn = ConnectionManager(
      factory: (_, _) async => channel,
      storage: _Storage(),
    );
    repo = TimelineRepository(
      conn,
      _Storage(),
      capabilityTimeout: const Duration(milliseconds: 30),
      requestTimeout: const Duration(milliseconds: 60),
    );
    conn.adopt(
      channel,
      const PeerRecord(
        remoteEpk: 'mac',
        sessionName: 'Mac',
        relayUrl: 'http://localhost',
        pairedAt: '2026-01-01',
      ),
    );
    await _flush();
  });
  tearDown(() {
    repo.dispose();
    conn.dispose();
  });

  test('capabilities use existing channel and correlate request id', () async {
    final future = repo.isSupported();
    await _flush();
    final sent = channel.sent.whereType<PerchCapabilitiesGet>().single;
    channel.respond('capabilities', 'wrong-id');
    channel.respond('capabilities', sent.id);
    expect(await future, isTrue);
    expect(repo.connection.label, 'Mac');
  });

  test(
    'legacy capability silence becomes unsupported without list request',
    () async {
      expect(await repo.isSupported(), isFalse);
      expect(channel.sent.whereType<PerchRequest>(), isEmpty);
    },
  );

  test(
    'list requires matching method and id; legacy messages are ignored',
    () async {
      final future = repo.snapshot();
      await _flush();
      final request = channel.sent.whereType<PerchRequest>().single;
      expect(request.method, 'agents.list');
      expect(request.params, isEmpty);
      channel.messages.add(
        ErrorMessage(code: 'unsupported_type', message: 'unknown'),
      );
      channel.respond('agents-list', request.id, method: 'agents.events');
      channel.respond('agents-list', 'wrong-id');
      channel.respond('agents-list', request.id);
      expect((await future).revision, 1);
    },
  );

  test('events resume cursor and cap long poll at 25 seconds', () async {
    final future = repo.events(
      epoch: 'broker-epoch-1',
      cursor: 1,
      waitMs: 99000,
    );
    await _flush();
    final request = channel.sent.whereType<PerchRequest>().single;
    expect(request.params, {
      'epoch': 'broker-epoch-1',
      'cursor': 1,
      'limit': 128,
      'wait_ms': 25000,
    });
    channel.respond('agents-events', request.id);
    expect((await future).events.single.verb, 'delivered');
  });

  test(
    'capability timeout after confirmed support stays a transport failure',
    () async {
      final first = repo.isSupported();
      await _flush();
      final request = channel.sent.whereType<PerchCapabilitiesGet>().single;
      channel.respond('capabilities', request.id);
      expect(await first, isTrue);
      await expectLater(
        repo.isSupported(),
        throwsA(
          isA<PerchReadFailure>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
    },
  );

  test('read timeout is a failure, never an idle event page', () async {
    await expectLater(
      repo.events(epoch: 'broker-epoch-1', cursor: 2),
      throwsA(isA<PerchReadFailure>().having((e) => e.code, 'code', 'timeout')),
    );
  });

  test('disconnection fails pending read as offline', () async {
    final result = repo.snapshot();
    final expectation = expectLater(
      result,
      throwsA(isA<PerchReadFailure>().having((e) => e.code, 'code', 'offline')),
    );
    await conn.disconnect();
    await expectation;
  });

  test('server error is correlated and propagated', () async {
    final result = repo.snapshot();
    await _flush();
    final request = channel.sent.whereType<PerchRequest>().single;
    channel.messages.add(
      PerchError(id: request.id, code: 'forbidden', message: 'denied'),
    );
    await expectLater(
      result,
      throwsA(
        isA<PerchReadFailure>().having((e) => e.code, 'code', 'forbidden'),
      ),
    );
  });

  test('send failure becomes explicit offline error', () async {
    channel.failSend = true;
    await expectLater(
      repo.snapshot(),
      throwsA(isA<PerchReadFailure>().having((e) => e.code, 'code', 'offline')),
    );
  });
}
