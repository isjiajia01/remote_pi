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
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
  int refreshes = 0;
  int retries = 0;
  @override
  HomeRelay get relay =>
      state is HomeList ? (state as HomeList).relay : HomeRelay.connecting;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<void> retry() async {
    retries++;
  }

  @override
  Future<void> setGrouping(HomeGrouping value) async {
    emit((state as HomeList).copyWith(grouping: value));
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

const mac = PeerRecord(
  remoteEpk: 'mac',
  sessionName: 'Mac',
  relayUrl: 'ws://x',
  pairedAt: '2026-01-01',
);
HomeList ready({
  HomeFilter filter = HomeFilter.all,
  HomeRelay relay = HomeRelay.connected,
}) => HomeList(
  peers: [mac],
  relay: relay,
  filter: filter,
  staleSince: DateTime(2026, 1, 1, 10),
  now: DateTime(2026, 1, 1, 10, 2),
  roomsByPeer: {
    'mac=': [
      const RoomInfo(
        roomId: 'one',
        cwd: '/Users/me/project',
        name: 'Agent one',
        model: 'claude-sonnet-4.5',
        startedAt: 1,
      ),
    ],
  },
  statusesByRoom: const {'mac:one': AgentStatus.online},
);

Future<void> _pumpHome(
  WidgetTester tester,
  _Home vm, {
  bool dark = false,
  bool reduceMotion = true,
  String? paired,
}) async {
  tester.view.physicalSize = const Size(430, 932);
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
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(430, 932),
            disableAnimations: reduceMotion,
          ),
          child: HomePage(pairedPeerEpk: paired),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('loading has three skeletons, static with reduced motion', (
    tester,
  ) async {
    await _pumpHome(tester, _Home(const HomeLoading()));
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('home-skeleton-$i')), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(find.text('Agents'), findsWidgets);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no machine shows pairing action and exact guidance', (
    tester,
  ) async {
    await _pumpHome(tester, _Home(const HomeNoPeer()));
    expect(find.text('No machines yet'), findsOneWidget);
    expect(
      find.text('Pair the Pi on your Mac to see its agents here.'),
      findsOneWidget,
    );
    expect(find.text('Pair a machine'), findsOneWidget);
    expect(find.byType(HomeFilterTabs), findsNothing);
  });
  testWidgets(
    'paired machine without rooms keeps its section and instructions',
    (tester) async {
      await _pumpHome(
        tester,
        _Home(const HomeList(peers: [mac], relay: HomeRelay.connected)),
      );
      expect(find.text('Mac'), findsOneWidget);
      expect(find.text('No agents running on Mac'), findsOneWidget);
      expect(find.bySemanticsLabel('New session'), findsOneWidget);
      expect(find.text('Open Pi and run /remote-pi'), findsOneWidget);
      expect(find.byType(AgentRow), findsNothing);
    },
  );
  testWidgets('filter empty Show all restores rows; four chips stay visible', (
    tester,
  ) async {
    final vm = _Home(ready(filter: HomeFilter.working));
    await _pumpHome(tester, vm);
    expect(find.text('Nothing working right now'), findsOneWidget);
    expect(find.byType(HomeFilterTabs), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentRow), findsOneWidget);
    expect((vm.state as HomeList).filter, HomeFilter.all);
    expect(find.text('Relay connected'), findsOneWidget);
  });
  testWidgets(
    'offline retains Online behind stale dot and as-of caption, Retry works',
    (tester) async {
      final vm = _Home(ready(relay: HomeRelay.offline));
      await _pumpHome(tester, vm, dark: true);
      expect(
        find.text('Relay offline — showing last known state'),
        findsOneWidget,
      );
      expect(find.text('Last known · as of 2m'), findsWidgets);
      expect(find.text('Last known'), findsOneWidget);
      final dot = tester.widget<StatusDot>(find.byType(StatusDot));
      expect(dot.status, AgentStatus.stale);
      expect(dot.lastKnownStatus, AgentStatus.online);
      await tester.tap(find.text('Retry'));
      expect(vm.retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('group menu selects project, row shows machine chip', (
    tester,
  ) async {
    final vm = _Home(ready());
    await _pumpHome(tester, vm);
    expect(find.bySemanticsLabel('Group agents'), findsNothing);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect((vm.state as HomeList).grouping, HomeGrouping.machine);
    expect(find.text('Mac'), findsOneWidget);
  });
  testWidgets('refresh control requests room recheck', (tester) async {
    final vm = _Home(ready());
    await _pumpHome(tester, vm);
    final refresh = tester.widget<CupertinoSliverRefreshControl>(
      find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
    );
    await refresh.onRefresh!();
    expect(vm.refreshes, 1);
  });
  testWidgets('new paired machine flashes surface2 then clears after 600ms', (
    tester,
  ) async {
    await _pumpHome(tester, _Home(ready()), paired: 'mac');
    expect(tester.widget<AgentRow>(find.byType(AgentRow)).highlighted, isTrue);
    await tester.pump(const Duration(milliseconds: 599));
    expect(tester.widget<AgentRow>(find.byType(AgentRow)).highlighted, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<AgentRow>(find.byType(AgentRow)).highlighted, isFalse);
  });
}
