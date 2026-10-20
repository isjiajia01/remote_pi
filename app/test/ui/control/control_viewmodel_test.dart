import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/repositories/control_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/control/viewmodels/control_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _Channel implements IChannel, IRoomChannel {
  final room = StreamController<ServerMessage>.broadcast();
  final chat = StreamController<ServerMessage>.broadcast();
  final sent = <ClientMessage>[];
  @override
  Stream<ServerMessage> get serverMessages => chat.stream;
  @override
  Stream<ServerMessage> messagesForRoom(String name) => room.stream;
  @override
  Future<void> send(ClientMessage msg) async => throw StateError('chat room');
  @override
  Future<void> sendToRoom(String name, ClientMessage message) async {
    expect(name, 'perch-control');
    sent.add(message);
  }

  @override
  Future<void> close() => room.close();

  void reply(Map<String, dynamic> response, String id) =>
      room.add(decodeServer(jsonEncode({...response, 'id': id})));
}

class _Storage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => [];
}

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(
              File(
                '../.orchestration/contracts/perch-v1/$name.json',
              ).readAsStringSync(),
            )
            as Map)['response']
        as Map<String, dynamic>;

Map<String, dynamic> _ok(
  String method,
  int revision,
  Map<String, dynamic> data,
) => {
  'type': 'perch_result',
  'version': 1,
  'method': method,
  'result': {'scope': 'supervisor', 'revision': revision, 'data': data},
};

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late _Channel channel;
  late ConnectionManager conn;
  late ControlRepository repo;
  late ControlViewModel vm;

  const daemon = {'id': '1234abcd', 'name': 'work', 'state': 'stopped'};
  const job = {
    'id': 'j_c3',
    'daemon_id': '1234abcd',
    'schedule': '0 * * * *',
    'prompt': 'Check inbox',
    'enabled': true,
  };

  PerchRequest lastRequest() => channel.sent.whereType<PerchRequest>().last;

  /// Answers the capability + daemon.list + cron.list triple of a refresh.
  Future<void> answerRefresh({int revision = 2}) async {
    await _flush();
    channel.reply(
      _fixture('control-capabilities'),
      (channel.sent.last as PerchCapabilitiesGet).id,
    );
    await _flush();
    channel.reply(
      _ok('daemon.list', revision, {
        'daemons': [daemon],
      }),
      lastRequest().id,
    );
    await _flush();
    channel.reply(
      _ok('cron.list', revision, {
        'jobs': [job],
      }),
      lastRequest().id,
    );
    await _flush();
  }

  setUp(() async {
    channel = _Channel();
    conn = ConnectionManager(
      factory: (_, _) async => channel,
      storage: _Storage(),
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
    repo = ControlRepository(
      conn,
      timeoutOverride: const Duration(milliseconds: 80),
    );
    vm = ControlViewModel(repo);
    await answerRefresh();
  });
  tearDown(() {
    vm.dispose();
    repo.dispose();
    conn.dispose();
  });

  test('refresh loads daemons and cron jobs with revision', () {
    expect(vm.state.ready, isTrue);
    expect(vm.state.daemons.single.id, '1234abcd');
    expect(vm.state.jobs.single.id, 'j_c3');
    expect(vm.state.revision, 2);
  });

  test('action sends expected_revision and a fresh id per action', () async {
    unawaited(vm.perform('daemon.start', {'id': '1234abcd'}));
    await _flush();
    final first = lastRequest();
    expect(first.expectedRevision, 2);
    expect(first.params, {'id': '1234abcd'});
    channel.reply(_fixture('daemon-start'), first.id);
    await answerRefresh(revision: 3);
    unawaited(vm.perform('daemon.start', {'id': '1234abcd'}));
    await _flush();
    expect(lastRequest().id, isNot(first.id));
    expect(lastRequest().expectedRevision, 3);
  });

  test(
    'timeout is unknown, never success, and retry reuses the same id',
    () async {
      unawaited(vm.perform('cron.run', {'job_id': 'j_c3'}));
      await _flush();
      final first = lastRequest();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(vm.state.message, 'Result unknown, refresh');
      expect(vm.state.ready, isFalse);
      expect(vm.state.retry, isNotNull);
      unawaited(vm.retry());
      await _flush();
      final retry = lastRequest();
      expect(retry.id, first.id);
      expect(retry.params, first.params);
      expect(retry.expectedRevision, first.expectedRevision);
    },
  );

  test(
    'ambiguous conflict outcome refreshes instead of reporting success',
    () async {
      unawaited(vm.perform('daemon.restart', {'id': '1234abcd'}));
      await _flush();
      channel.reply(_fixture('control-ambiguous'), lastRequest().id);
      await _flush();
      // conflict forces a fresh capability + list round trip
      expect(channel.sent.last, isA<PerchCapabilitiesGet>());
      expect(vm.state.busy, isTrue);
      await answerRefresh(revision: 5);
      expect(vm.state.revision, 5);
      expect(vm.state.message, contains('refreshed'));
    },
  );

  test('revision conflict golden refreshes lists', () async {
    unawaited(vm.perform('daemon.stop', {'id': '1234abcd'}));
    await _flush();
    channel.reply(_fixture('control-conflict'), lastRequest().id);
    await _flush();
    expect(channel.sent.last, isA<PerchCapabilitiesGet>());
  });

  test('forbidden shows the opt-in disabled state', () async {
    unawaited(vm.refresh());
    await _flush();
    channel.reply({
      'type': 'perch_error',
      'version': 1,
      'error': {'code': 'forbidden', 'message': 'no'},
    }, (channel.sent.last as PerchCapabilitiesGet).id);
    await _flush();
    expect(vm.state.disabled, isTrue);
    expect(vm.state.message, 'Remote control not enabled on this Mac');
    expect(vm.state.can('daemon.start'), isFalse);
  });

  test(
    'cron.add validates schedule and prompt length before sending',
    () async {
      final before = channel.sent.length;
      await vm.addCron('1234abcd', ' ', 'x');
      await vm.addCron('1234abcd', '0 * * * *', 'x' * 8193);
      expect(channel.sent.length, before);
      unawaited(vm.addCron('1234abcd', '0 * * * *', 'Check inbox'));
      await _flush();
      expect(lastRequest().method, 'cron.add');
      expect(lastRequest().params['prompt'], 'Check inbox');
    },
  );

  test('capability set gates methods not granted', () {
    expect(vm.state.can('cron.log'), isTrue);
    expect(vm.state.can('agents.list'), isFalse);
    expect(const ControlFailure('timeout', '').unknown, isTrue);
  });
}
