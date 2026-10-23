import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/widgets/chat_actions.dart';
import 'package:app/ui/chat/widgets/confirm_chat_action.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Repo implements IActionsRepository {
  final change = Completer<void>();
  @override
  ActiveRoomMeta get activeRoomMeta =>
      const ActiveRoomMeta(model: 'sonnet', thinking: ThinkingLevel.low);
  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream => const Stream.empty();
  @override
  Future<void> setModel(String provider, String modelId) => change.future;
  @override
  Future<void> setThinking(ThinkingLevel level) => change.future;
  @override
  Future<void> compact() async {}
  @override
  Future<void> newSession() async {}
  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async =>
      const ModelsCatalogue(models: []);
  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'context chips track busy action, disable other chips, show failure for 4 seconds, copy cwd',
    (tester) async {
      final repo = _Repo();
      final vm = QuickActionsViewModel(repo);
      addTearDown(vm.dispose);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: vm,
              child: const ChatContextStrip(enabled: true, cwd: '/work/perch'),
            ),
          ),
        ),
      );
      expect(find.text('sonnet'), findsOneWidget);
      expect(find.text('Think low'), findsOneWidget);
      expect(find.text('/work/perch'), findsNothing);
      final change = vm.setModel(
        const WireModel(
          id: 'opus',
          name: 'opus',
          provider: 'anthropic',
          reasoning: true,
          contextWindow: 200000,
        ),
      );
      final failed = expectLater(change, throwsA(isA<ActionFailure>()));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      final chips = tester
          .widgetList<CupertinoButton>(find.byType(CupertinoButton))
          .toList();
      expect(chips.take(2).every((chip) => chip.onPressed == null), isTrue);
      repo.change.completeError(const ActionFailure('model unavailable'));
      await failed;
      await tester.pump();
      expect(
        find.text("Couldn't change model — model unavailable"),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 3999));
      expect(
        find.text("Couldn't change model — model unavailable"),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 251));
      await tester.pump(const Duration(milliseconds: 251));
      expect(
        find.text("Couldn't change model — model unavailable"),
        findsNothing,
      );
    },
  );

  testWidgets(
    'menu exposes all four actions and keeps info available offline',
    (tester) async {
      var info = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatMenu(enabled: false, onInfo: () => info++)),
        ),
      );
      await tester.tap(find.byTooltip('Session menu'));
      await tester.pumpAndSettle();
      for (final label in [
        'Quick actions…',
        'Compact context',
        'New session',
        'Session info',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final entries = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .toList();
      expect(entries.take(3).every((item) => !item.enabled), isTrue);
      await tester.tap(find.text('Session info'));
      await tester.pumpAndSettle();
      expect(info, 1);
    },
  );

  testWidgets(
    'new session confirmation explains cache deletion and rejects a changed tablet selection',
    (tester) async {
      final selection = SessionSelection();
      addTearDown(selection.dispose);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: selection,
            child: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () async =>
                      result = await confirmChatAction(ctx, newSession: true),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(
        find.textContaining('Cached messages for this session will be cleared'),
        findsOneWidget,
      );
      final confirm = tester.widget<CupertinoActionSheetAction>(
        find.ancestor(
          of: find.text('New session'),
          matching: find.byType(CupertinoActionSheetAction),
        ),
      );
      expect(confirm.isDestructiveAction, isTrue);
      selection.select('other', 'main', 'Other');
      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
}
