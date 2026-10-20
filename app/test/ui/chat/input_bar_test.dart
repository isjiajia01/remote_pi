// Plan/28 Wave C — settings/quick-actions icon visibility in the
// chat input bar.

import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required bool disabled,
    required bool streaming,
    VoidCallback? onOpenQuickActions,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: disabled,
            streaming: streaming,
            onSend: (_) {},
            onCancel: () {},
            onOpenQuickActions: onOpenQuickActions,
          ),
        ),
      ),
    );
  }

  test('composer maps all working/content combinations', () {
    expect(composerMode(working: false, hasContent: false), ComposerMode.mic);
    expect(composerMode(working: false, hasContent: true), ComposerMode.send);
    expect(composerMode(working: true, hasContent: false), ComposerMode.stop);
    expect(composerMode(working: true, hasContent: true), ComposerMode.steer);
  });

  testWidgets('quick actions moved out of the composer', (tester) async {
    await pumpBar(
      tester,
      disabled: false,
      streaming: false,
      onOpenQuickActions: () {},
    );
    expect(find.byKey(const Key('input-bar-quick-actions')), findsNothing);
    expect(find.byIcon(LucideIcons.mic600), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.byIcon(LucideIcons.arrowUp), findsOneWidget);
  });

  testWidgets('offline composer disables typing and send', (tester) async {
    var sent = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(disabled: true, onSend: (_) => sent = true),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(field.decoration?.hintText, 'Agent offline');
    await tester.tap(find.byKey(const Key('input-bar-action')));
    expect(sent, isFalse);
  });

  // Plan/43 — `streaming` (the whole working turn, fed by vm.isWorking) keeps
  // the composer editable for steering while empty input still exposes Stop.
  testWidgets('streaming with no text shows stop and keeps typing enabled', (
    tester,
  ) async {
    await pumpBar(
      tester,
      disabled: false,
      streaming: true,
      onOpenQuickActions: () {},
    );
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.decoration?.hintText, 'Steer current response…');
    // The composer action button uses the heavier `600` weight variants
    // (see _ComposerActionButton._icon) — match those, not the plain glyphs.
    expect(find.byIcon(LucideIcons.square600), findsOneWidget); // stop
    expect(find.byIcon(LucideIcons.arrowUp), findsNothing);
    expect(find.byIcon(LucideIcons.mic600), findsNothing);
  });

  testWidgets('streaming + text uses existing send button for steer', (
    tester,
  ) async {
    String? queued;
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: true,
            onSend: (text) => sent = text,
            onCancel: () {},
            onSetQueued: (text) => queued = text,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'steer me');
    await tester.pump();
    expect(find.byKey(const Key('input-bar-queue')), findsNothing);
    await tester.tap(find.byKey(const Key('input-bar-action')));
    await tester.pump();

    expect(sent, 'steer me');
    expect(queued, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('queued preview edits and clears by id', (tester) async {
    String? cleared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: true,
            queuedMessages: [
              QueuedMsg(
                id: 'q1',
                text: 'queued text',
                editable: true,
                createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              ),
            ],
            onSend: (_) {},
            onCancel: () {},
            onClearQueued: (id) => cleared = id,
          ),
        ),
      ),
    );

    expect(find.text('queued text'), findsOneWidget);
    await tester.tap(find.byKey(const Key('input-bar-queued-preview')));
    await tester.pump();

    expect(cleared, 'q1');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'queued text',
    );
  });

  testWidgets('read-only queued preview has no clear affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: true,
            queuedMessages: [
              QueuedMsg(
                id: 'q1',
                text: 'queued text',
                editable: false,
                createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              ),
            ],
            onSend: (_) {},
            onCancel: () {},
            onClearQueued: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('input-bar-clear-queued')), findsNothing);
    await tester.tap(find.byKey(const Key('input-bar-queued-preview')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('streaming + text turns send into steering', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: true,
            onSend: (text) => sent = text,
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'quick follow-up');
    await tester.pump();
    expect(find.byIcon(LucideIcons.cornerDownRight), findsOneWidget);
    expect(
      find.byKey(const Key('input-bar-inline-stop')),
      findsOneWidget,
      reason: 'Stop remains reachable while the main action sends steering',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, 'quick follow-up');
  });

  // Hardware keyboard (iPad keyboard case): plain Enter SENDS, Shift+Enter
  // inserts a newline. Touch behaviour is unaffected (soft Enter = newline via
  // performAction, send via the button).
  testWidgets('hardware Enter sends; Shift+Enter inserts a newline', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: false,
            onSend: sent.add,
            onCancel: () {},
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'hello');
    await tester.pump();

    // Plain Enter → send + clear.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, ['hello']);
    expect(
      tester.widget<TextField>(field).controller!.text,
      isEmpty,
      reason: 'submit clears the field',
    );

    // Shift+Enter → newline, NOT a send.
    await tester.enterText(field, 'line1');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sent, ['hello'], reason: 'shift+enter must not send');
    expect(
      tester.widget<TextField>(field).controller!.text,
      'line1\n',
      reason: 'shift+enter inserts a newline at the caret',
    );
  });

  // While there is no content, hardware Enter does nothing while streaming.
  testWidgets('hardware Enter does nothing while streaming with empty text', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            disabled: false,
            streaming: true,
            onSend: sent.add,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, isEmpty);
  });
}
