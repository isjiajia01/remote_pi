import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/timeline/states/timeline_state.dart';
import 'package:app/ui/timeline/timeline_page.dart';
import 'package:app/ui/timeline/viewmodels/timeline_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'timeline_viewmodel_test.dart' show FakeTimelineReader, golden;

Future<void> pump(
  WidgetTester tester,
  TimelineData state, {
  bool dark = false,
  double scale = 1,
}) async {
  final reader = FakeTimelineReader();
  final vm = TimelineViewModel(reader);

  addTearDown(reader.updates.close);
  await tester.pumpWidget(
    ChangeNotifierProvider<TimelineViewModel>(
      key: ObjectKey(vm),
      create: (_) => vm,
      child: MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const TimelinePage(),
        ),
      ),
    ),
  );
  await tester.pump();
  vm.emit(state);
  await tester.pump();
}

void main() {
  testWidgets(
    'golden event renders actor target delivered and day in light/dark',
    (tester) async {
      for (final dark in [false, true]) {
        await pump(
          tester,
          TimelineData(
            status: TimelineStatus.ready,
            events: golden('agents-events').eventPage.events,
            lastUpdated: DateTime(2026, 10, 19),
          ),
          dark: dark,
        );
        expect(
          find.text('/work/perch@planner → /work/perch@coder'),
          findsOneWidget,
        );
        expect(find.text('delivered'), findsOneWidget);
        expect(find.text('done'), findsNothing);
        expect(find.textContaining('As of'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('capability absence shows exact empty state', (tester) async {
    await pump(tester, TimelineData(status: TimelineStatus.unsupported));
    expect(find.text('Not supported by this Pi version'), findsOneWidget);
    expect(find.text('No events yet'), findsNothing);
  });
  testWidgets('offline and stale retain rows and show explicit text', (
    tester,
  ) async {
    for (final status in [TimelineStatus.offline, TimelineStatus.stale]) {
      await pump(
        tester,
        TimelineData(
          status: status,
          events: golden('agents-events').eventPage.events,
          lastUpdated: DateTime(2026, 10, 19),
          historyGap: true,
        ),
      );
      expect(find.text('delivered'), findsOneWidget);
      expect(
        find.text(
          status == TimelineStatus.offline
              ? 'Offline — showing last known state'
              : 'Stale — unable to refresh timeline',
        ),
        findsOneWidget,
      );
      expect(
        find.text('History gap — some events unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('large text keeps timeline readable without overflow', (
    tester,
  ) async {
    await pump(
      tester,
      TimelineData(
        status: TimelineStatus.ready,
        events: golden('agents-events').eventPage.events,
      ),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
