import 'dart:ui' show SemanticsAction;

import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/widgets/agent_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const mac = PeerRecord(
  remoteEpk: 'mac',
  sessionName: 'Mac',
  relayUrl: 'ws://x',
  pairedAt: '2026-01-01',
);
final now = DateTime(2026, 1, 1, 10, 4);
final activity = SessionIndexRecord(
  epk: 'mac',
  roomId: 'r1',
  lastMessageAt: DateTime(2026, 1, 1, 10),
  lastMessagePreview: 'Updated the dashboard',
);
HomeItem item(AgentStatus status) => HomeItem(
  peer: mac,
  room: const RoomInfo(
    roomId: 'r1',
    startedAt: 1,
    name: 'Agent',
    cwd: '/Users/me/project',
    model: 'claude-sonnet-4.5',
    thinking: ThinkingLevel.low,
  ),
  lastKnownStatus: status,
  activity: activity,
);

Future<void> pumpRow(
  WidgetTester tester, {
  AgentStatus status = AgentStatus.online,
  double width = 430,
  VoidCallback? onOpen,
  HomeItem? rowItem,
}) async {
  tester.view.physicalSize = Size(width, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: Size(width, 932), disableAnimations: true),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: AgentRow(
                item: rowItem ?? item(status),
                now: now,
                onOpen: onOpen ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Online is labelled, model/thinking/path/time render and preview is responsive',
    (tester) async {
      await pumpRow(tester);
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(find.text('sonnet-4.5'), findsOneWidget);
      expect(find.text('Think low'), findsOneWidget);
      expect(find.text('~/project'), findsOneWidget);
      expect(find.text('4m'), findsOneWidget);
      expect(find.text(activity.lastMessagePreview!), findsOneWidget);
      await pumpRow(tester, width: 360);
      expect(find.text(activity.lastMessagePreview!), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'model ids shorten in mono and profile names keep UI typography',
    (tester) async {
      for (final model in [
        'anthropic/claude-sonnet-4.5-20250929',
        'Claude Sonnet 4.5 (work profile)',
      ]) {
        await pumpRow(
          tester,
          rowItem: HomeItem(
            peer: mac,
            room: item(AgentStatus.online).room.copyWith(model: model),
          ),
        );
        final isId = model.startsWith('anthropic/');
        final text = tester.widget<Text>(
          find.text(isId ? 'sonnet-4.5' : model),
        );
        expect(text.style!.fontFamily, isId ? kMonoFamily : isNot(kMonoFamily));
      }
    },
  );

  testWidgets(
    'preview hides empty and one-character samples, keeps prose on one line',
    (tester) async {
      for (final preview in [
        '',
        ' ',
        '1',
        ' 1 ',
        'A longer preview that can be truncated',
      ]) {
        await pumpRow(
          tester,
          rowItem: HomeItem(
            peer: mac,
            room: item(AgentStatus.online).room,
            activity: activity.copyWith(lastMessagePreview: preview),
          ),
        );
        if (preview.trim().length < 2) {
          expect(find.text(preview.trim()), findsNothing);
        } else {
          final finder = find.text(preview);
          final text = tester.widget<Text>(finder);
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          final context = tester.element(finder);
          expect(
            text.style,
            context.typo.subhead.copyWith(color: context.colors.ink2),
          );
          final padding = tester.widget<Padding>(
            find.ancestor(of: finder, matching: find.byType(Padding)).first,
          );
          expect(padding.padding, const EdgeInsets.only(top: 8));
        }
      }
    },
  );

  testWidgets('home cwd stays tilde and long cwd truncates only in the middle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AgentRow(
                  item: const HomeItem(
                    peer: mac,
                    room: RoomInfo(
                      roomId: 'home',
                      startedAt: 1,
                      cwd: '/Users/me',
                    ),
                  ),
                  onOpen: () {},
                ),
                AgentRow(
                  item: const HomeItem(
                    peer: mac,
                    room: RoomInfo(
                      roomId: 'long',
                      startedAt: 1,
                      cwd:
                          '/Users/me/a-very-long-project-directory/another-long-directory/project',
                    ),
                  ),
                  onOpen: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('~'), findsOneWidget);
    final path = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .singleWhere((text) => text.startsWith('~/') && text.contains('…'));
    expect(path.endsWith('project'), isTrue);
    expect(path.indexOf('…'), greaterThan(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'one actionable semantic label names status, machine and activity',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var opens = 0;
      await pumpRow(tester, onOpen: () => opens++);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'Agent, Online, Mac, last activity 4 minutes ago',
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.text('Agent'));
      expect(opens, 1);
      semantics.dispose();
    },
  );
  testWidgets('working and offline use status pills', (tester) async {
    await pumpRow(tester, status: AgentStatus.working);
    expect(
      tester.widget<StatusPill>(find.byType(StatusPill)).state,
      StatusPillState.working,
    );
    await pumpRow(tester, status: AgentStatus.offline);
    expect(
      tester.widget<StatusPill>(find.byType(StatusPill)).state,
      StatusPillState.offline,
    );
  });
  testWidgets(
    'context menu copies raw cwd and display name, Open invokes callback',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var opens = 0;
      await pumpRow(tester, onOpen: () => opens++);
      Future<void> openMenu() async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Agent')),
        );
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoContextMenuAction), findsNWidgets(3));
      }

      await openMenu();
      await tester.tap(find.text('Copy path'));
      await tester.pumpAndSettle();
      expect(clipboard, '/Users/me/project');
      await openMenu();
      await tester.tap(find.text('Copy session name'));
      await tester.pumpAndSettle();
      expect(clipboard, 'Agent');
      await openMenu();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opens, 1);
    },
  );
  test('activity formatting covers none, minutes, hours and weekday', () {
    expect(activityTime(null, now), '—');
    expect(activityTime(now.subtract(const Duration(hours: 2)), now), '2h');
    expect(activityTime(now.subtract(const Duration(days: 3)), now), 'Mon');
    expect(shortPath('/home/me/project'), '~/project');
  });
}
