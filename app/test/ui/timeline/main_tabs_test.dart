import 'package:app/config/features.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/navigation/main_tabs.dart';
import 'package:app/ui/timeline/states/timeline_state.dart';
import 'package:app/ui/timeline/viewmodels/timeline_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'timeline_viewmodel_test.dart' show FakeTimelineReader, golden;

void main() {
  testWidgets(
    'minimal offers Agents and Settings without a timeline provider',
    (tester) async {
      if (perchFullFeatures) return;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                MainTabs(location: state.uri.path, child: child),
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const Text('Agents body'),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Text('Settings body'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Timeline'), findsNothing);
      expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .items
            .length,
        2,
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings body'), findsOneWidget);
    },
  );
  testWidgets(
    'three Cupertino tabs retain cursor and cache; background stops polling',
    skip: !perchFullFeatures,
    (tester) async {
      final reader = FakeTimelineReader();
      var creations = 0;
      late TimelineViewModel vm;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                ChangeNotifierProvider<TimelineViewModel>(
                  create: (_) {
                    creations++;
                    return vm = TimelineViewModel(reader);
                  },
                  child: MainTabs(location: state.uri.path, child: child),
                ),
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const Text('Agents body'),
              ),
              GoRoute(
                path: '/timeline',
                builder: (_, _) => const Text('Timeline body'),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Text('Settings body'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(reader.updates.close);
      await tester.pumpWidget(
        MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoTabBar), findsOneWidget);
      expect(reader.supportCalls, 0);
      router.go('/timeline');
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(reader.requests.single.cursor, 1);
      reader.pending[0].complete(golden('agents-events').eventPage);
      await tester.pumpAndSettle();
      expect(vm.state.events.length, 1);
      router.go('/settings');
      await tester.pumpAndSettle();
      reader.pending[1].complete(golden('agents-events').eventPage);
      await tester.pumpAndSettle();
      expect(reader.requests.length, 2);
      router.go('/timeline');
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(reader.requests.last.cursor, 2);
      expect(vm.state.events.length, 1);
      expect(vm.state.status, TimelineStatus.stale);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      reader.pending[2].complete(golden('agents-events').eventPage);
      await tester.pumpAndSettle();
      expect(reader.requests.length, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reader.requests.length, 4);
      expect(reader.requests.last.cursor, 2);
    },
  );
}
