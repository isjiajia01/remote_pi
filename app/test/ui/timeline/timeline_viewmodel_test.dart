import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/domain/contracts/timeline_reader.dart';
import 'package:app/domain/entities/agent_timeline.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/timeline/states/timeline_state.dart';
import 'package:app/ui/timeline/viewmodels/timeline_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

PerchResult golden(String name) =>
    ServerMessage.fromJson(
          (jsonDecode(
                    File(
                      '../.orchestration/contracts/perch-v1/$name.json',
                    ).readAsStringSync(),
                  )
                  as Map)['response']
              as Map<String, dynamic>,
        )
        as PerchResult;

class FakeTimelineReader extends TimelineReader {
  final updates = StreamController<TimelineConnection>.broadcast();
  @override
  TimelineConnection connection = const TimelineConnection(
    key: 'mac|room',
    machineId: 'mac',
    label: 'Mac',
    online: true,
  );
  @override
  Stream<TimelineConnection> get connections => updates.stream;
  bool supported = true;
  int supportCalls = 0;
  int snapshots = 0;
  final requests = <({String epoch, int cursor, int waitMs})>[];
  final pending = <Completer<AgentEventPage>>[];
  final snapshotQueue = <AgentSnapshot>[];
  @override
  Future<List<TimelineMachine>> machines() async => [
    const TimelineMachine('mac', 'Mac'),
  ];
  @override
  Future<void> selectMachine(String id) async {}
  @override
  Future<bool> isSupported() async {
    supportCalls++;
    return supported;
  }

  @override
  Future<AgentSnapshot> snapshot() async {
    snapshots++;
    return snapshotQueue.isEmpty
        ? golden('agents-list').snapshot
        : snapshotQueue.removeAt(0);
  }

  @override
  Future<AgentEventPage> events({
    required String epoch,
    required int cursor,
    int waitMs = 25000,
  }) {
    requests.add((epoch: epoch, cursor: cursor, waitMs: waitMs));
    final completer = Completer<AgentEventPage>();
    pending.add(completer);
    return completer.future;
  }

  void change({required bool online, String key = 'mac|room'}) {
    connection = TimelineConnection(
      key: key,
      machineId: 'mac',
      label: 'Mac',
      online: online,
    );
    updates.add(connection);
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTimelineReader reader;
  late TimelineViewModel vm;
  setUp(() {
    reader = FakeTimelineReader();
    vm = TimelineViewModel(reader);
  });
  tearDown(() async {
    vm.dispose();
    await reader.updates.close();
  });

  test(
    'no reads until visible; snapshot seeds cursor; replay dedups audit ids',
    () async {
      await flush();
      expect(reader.supportCalls, 0);
      vm.setActive(true);
      await flush();
      expect(reader.snapshots, 1);
      expect(reader.requests.single, (
        epoch: 'broker-epoch-1',
        cursor: 1,
        waitMs: 25000,
      ));
      reader.pending[0].complete(golden('agents-events').eventPage);
      await flush();
      reader.pending[1].complete(golden('agents-events').eventPage);
      await flush();
      expect(vm.state.events.length, 1);
      expect(reader.requests.last.cursor, 2);
      // A second audit event with the same message id is a distinct delivery.
      final event = golden('agents-events').eventPage.events.single;
      reader.pending[2].complete(
        AgentEventPage(
          epoch: 'broker-epoch-1',
          cursor: 3,
          resyncRequired: false,
          events: [
            AgentEvent(
              cursor: 3,
              ts: event.ts,
              type: 'routed',
              id: event.id,
              from: event.from,
              to: event.to,
              ackStatus: 'received',
            ),
          ],
        ),
      );
      await flush();
      expect(vm.state.events.map((e) => e.cursor), [3, 2]);
      expect(vm.state.events.map((e) => e.verb), everyElement('delivered'));
      vm.filterAgent('/work/perch@coder');
      expect(vm.state.visibleEvents.length, 2);
      vm.filterAgent('other');
      expect(vm.state.visibleEvents, isEmpty);
      vm.setActive(false);
      reader.pending.last.complete(
        AgentEventPage(
          epoch: 'broker-epoch-1',
          cursor: 3,
          resyncRequired: false,
          events: [],
        ),
      );
      await flush();
      final calls = reader.requests.length;
      await flush();
      expect(reader.requests.length, calls);
    },
  );

  test(
    'shared gap response resyncs via agents.list before polling snapshot cursor',
    () async {
      vm.setActive(true);
      await flush();
      reader.snapshotQueue.add(
        AgentSnapshot(
          epoch: 'broker-epoch-1',
          revision: 2,
          cursor: 514,
          agents: [],
        ),
      );
      reader.pending.single.complete(golden('replay-gap').eventPage);
      await flush();
      expect(reader.snapshots, 2);
      expect(reader.requests.last.cursor, 514);
      expect(vm.state.historyGap, isTrue);
      expect(vm.state.status, TimelineStatus.ready);
    },
  );

  test(
    'transport timeout retains cached rows as stale; retry resumes cursor',
    () async {
      vm.setActive(true);
      await flush();
      reader.pending[0].complete(golden('agents-events').eventPage);
      await flush();
      reader.pending[1].completeError(
        const PerchReadFailure('timeout', 'timeout'),
      );
      await flush();
      expect(vm.state.status, TimelineStatus.stale);
      expect(vm.state.events.length, 1);
      expect(vm.state.lastUpdated, isNotNull);
      await vm.refresh();
      await flush();
      expect(reader.snapshots, 1);
      expect(reader.requests.last.cursor, 2);
    },
  );

  test(
    'offline stays explicit; reconnect resumes and ignores old connection result',
    () async {
      vm.setActive(true);
      await flush();
      reader.pending[0].complete(golden('agents-events').eventPage);
      await flush();
      reader.change(online: false);
      await flush();
      expect(vm.state.status, TimelineStatus.offline);
      expect(vm.state.events.length, 1);
      reader.change(online: true);
      await flush();
      expect(reader.requests.last.cursor, 2);
      expect(reader.snapshots, 1);
      reader.pending[1].complete(golden('replay-gap').eventPage);
      await flush();
      expect(reader.snapshots, 1);
    },
  );

  test('absent capability never calls list/events', () async {
    reader.supported = false;
    vm.setActive(true);
    await flush();
    expect(vm.state.status, TimelineStatus.unsupported);
    expect(reader.snapshots, 0);
    expect(reader.requests, isEmpty);
  });

  test('broker epoch restart clears cached history after snapshot', () async {
    vm.setActive(true);
    await flush();
    reader.pending[0].complete(golden('agents-events').eventPage);
    await flush();
    reader.snapshotQueue.add(
      AgentSnapshot(epoch: 'new', revision: 1, cursor: 0, agents: []),
    );
    reader.pending[1].complete(
      AgentEventPage(epoch: 'new', cursor: 0, events: [], resyncRequired: true),
    );
    await flush();
    expect(vm.state.events, isEmpty);
    expect(reader.requests.last.epoch, 'new');
  });
}
