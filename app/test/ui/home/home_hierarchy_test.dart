// Agents page IA: project cards, sub-agents nested under their parent run
// (never peers), offline rows tucked away, End only for live phone sessions.
import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/home_page.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/home/widgets/widgets.dart';
import 'package:app/ui/update/states/update_banner_state.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const uuid = '000f7ed8-04b8-4d2a-9c1e-1234567890ab';
const mac = PeerRecord(
  remoteEpk: 'mac',
  sessionName: 'Mac',
  relayUrl: 'ws://x',
  pairedAt: '2026-01-01',
);
final t0 = DateTime(2026, 10, 23, 8);

RoomInfo room(
  String id,
  String name, {
  String cwd = '/u/10.15_Perch',
  String? model,
}) => RoomInfo(
  roomId: id,
  name: name,
  cwd: cwd,
  model: model,
  startedAt: t0.millisecondsSinceEpoch,
);

/// Mirrors the user's screenshot: a main Perch terminal with two sub-agent
/// runs, an old-extension `#2` terminal, a phone session, a finished
/// sub-agent, an orphan sub-agent, and an offline-only project.
final _rooms = [
  room('perchMain001', '10.15_Perch', model: 'Claude Opus · 5.5'),
  room('sub.aaaaaaaaaaaa.perchMain001', '10.15_Perch#3', model: 'group/std'),
  room('sub.bbbbbbbbbbbb.perchMain001', '10.15_Perch#4'),
  room('sub.cccccccccccc.perchMain001', '10.15_Perch#5'),
  room('sub.dddddddddddd', '10.15_Perch#6'),
  room('perchLegacy2', '10.15_Perch#2'),
  room('session-$uuid', '10.15_Perch-$uuid'),
  room('slipMain0001', '10.14_Slip', cwd: '/u/10.14_Slip'),
  room('oldProject01', 'Old', cwd: '/u/Old'),
];

HomeList fixture({HomeFilter filter = HomeFilter.all}) => HomeList(
  peers: const [mac],
  relay: HomeRelay.connected,
  filter: filter,
  now: t0.add(const Duration(hours: 13)),
  // Page lookups normalize the EPK ('mac' → 'mac='); model tests do not.
  roomsByPeer: {'mac': _rooms, 'mac=': _rooms},
  statusesByRoom: {
    'mac:perchMain001': AgentStatus.online,
    'mac:sub.aaaaaaaaaaaa.perchMain001': AgentStatus.working,
    'mac:sub.bbbbbbbbbbbb.perchMain001': AgentStatus.online,
    'mac:sub.cccccccccccc.perchMain001': AgentStatus.offline,
    'mac:sub.dddddddddddd': AgentStatus.online,
    'mac:perchLegacy2': AgentStatus.offline,
    'mac:session-$uuid': AgentStatus.online,
    'mac:slipMain0001': AgentStatus.online,
    'mac:oldProject01': AgentStatus.offline,
  },
);

class _Storage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() => Completer<List<PeerRecord>>().future;
}

class _Connection extends Fake implements ConnectionManager {
  @override
  ConnectionStatus get status => const StatusConnecting();
  @override
  Stream<Map<String, PresenceState>> get presenceStream => const Stream.empty();
  @override
  Stream<Map<String, List<RoomInfo>>> get roomsStream => const Stream.empty();
  @override
  Stream<ConnectionStatus> get statusStream => const Stream.empty();
}

class _Home extends HomeViewModel {
  _Home(HomeState initial) : super(_Storage(), Preferences(), _Connection()) {
    emit(initial);
  }
  final removed = <String>[];
  @override
  HomeRelay get relay => HomeRelay.connected;
  @override
  bool isRoomLive(String epk, String roomId) => false;
  @override
  bool canEnd(HomeItem item) => item.kind.isPhone && item.isLive;
  @override
  Future<int> removeOffline(Iterable<HomeItem> items) async {
    removed.addAll(items.map((i) => i.room.roomId));
    return removed.length;
  }
}

class _Update extends ChangeNotifier implements UpdateBannerViewModel {
  @override
  UpdateBannerState get state => const UpdateBannerHidden();
  @override
  Future<void> check() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _Home vm) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeViewModel>(create: (_) => vm),
        ChangeNotifierProvider<UpdateBannerViewModel>(create: (_) => _Update()),
        ChangeNotifierProvider(create: (_) => ShellLayout()),
        ChangeNotifierProvider(create: (_) => SessionSelection()),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(430, 1400), disableAnimations: true),
          child: HomePage(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('model', () {
    test('sub-agents nest under their parent; finished runs are dropped', () {
      final perch = fixture().groups().firstWhere(
        (g) => g.label == '10.15_Perch',
      );
      final main = perch.sessions.firstWhere(
        (s) => s.item.room.roomId == 'perchMain001',
      );
      expect(main.subagents.map((s) => s.displayName), [
        'Sub-agent 3',
        'Sub-agent 4',
      ]);
      expect(main.hasWorking, isTrue);
      expect(perch.orphans.single.room.roomId, 'sub.dddddddddddd');
      expect(perch.sessions.map((s) => s.item.displayName), {
        'Terminal',
        'Phone session · 000f',
      });
      expect(perch.offline.single.displayName, 'Terminal 2');
    });

    test('order: working project first, offline-only project last', () {
      expect(fixture().groups().map((g) => g.label), [
        '10.15_Perch',
        '10.14_Slip',
        'Old',
      ]);
      expect(fixture().groups().last.isLive, isFalse);
    });

    test('counts and filters see main sessions only', () {
      final items = fixture().items();
      expect(items.where((i) => i.kind.isSubagent), isEmpty);
      expect(items, hasLength(5));
      final working = fixture(filter: HomeFilter.working).groups();
      // Parent is idle but its sub-agent works: the parent is shown.
      expect(working.single.sessions.single.item.room.roomId, 'perchMain001');
    });

    test('idle age uses the latest of connect, message and seen turn', () {
      final item = fixture().items().firstWhere(
        (i) => i.room.roomId == 'slipMain0001',
      );
      expect(item.idleSince, t0);
      final seen = HomeItem(
        peer: mac,
        room: item.room,
        workingSeenAt: t0.add(const Duration(hours: 2)),
      );
      expect(seen.idleSince, t0.add(const Duration(hours: 2)));
    });
  });

  group('page', () {
    testWidgets('sub-agents are collapsed under the parent, never peer rows', (
      tester,
    ) async {
      await _pump(tester, _Home(fixture()));
      final rows = tester.widgetList<AgentRow>(find.byType(AgentRow));
      expect(rows.map((r) => r.item.displayName).toSet(), {
        'Terminal',
        'Phone session · 000f',
      });
      expect(find.text('10.15_Perch'), findsOneWidget);
      expect(find.byType(SubagentRow), findsNothing);
      await tester.tap(find.text('2 sub-agents · 1 working'));
      await tester.pump();
      expect(find.byType(SubagentRow), findsNWidgets(2));
      expect(find.text('Sub-agent 3'), findsOneWidget);
      // Old-extension orphan stays in its own project-level disclosure.
      expect(find.text('1 sub-agent · parent not shown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('idle terminal says it is still running; End only on phone', (
      tester,
    ) async {
      await _pump(tester, _Home(fixture()));
      expect(find.text('Still running in a terminal · idle 13h'), findsWidgets);
      expect(find.text('Still running on Mac · idle 13h'), findsOneWidget);
      for (final row in tester.widgetList<AgentRow>(find.byType(AgentRow))) {
        expect(row.onEnd != null, row.item.kind.isPhone, reason: row.item.key);
        expect(row.onRemove, isNull, reason: 'live rows are not removable');
      }
    });

    testWidgets('offline rows are tucked away; Remove confirms first', (
      tester,
    ) async {
      final vm = _Home(fixture());
      await _pump(tester, vm);
      expect(find.text('Offline · 1'), findsOneWidget);
      expect(find.text('Not running · 1 project'), findsOneWidget);
      expect(find.text('Terminal 2'), findsNothing);
      expect(find.text('Old'), findsNothing);
      await tester.tap(find.text('Not running · 1 project'));
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
      final old = tester
          .widgetList<AgentRow>(find.byType(AgentRow))
          .firstWhere((r) => r.item.room.roomId == 'oldProject01');
      expect(old.onRemove, isNotNull);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(find.text('Remove 1 offline session?'), findsOneWidget);
      expect(vm.removed, isEmpty);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(vm.removed, ['oldProject01']);
    });
  });
}
