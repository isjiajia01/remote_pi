import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _bashTool = ToolEvent(
  id: 'tc1',
  toolCallId: 'tc1',
  tool: 'Bash',
  args: {'command': 'ls -la'},
);

const _editToolWithHunk = ToolEvent(
  id: 'tc2',
  toolCallId: 'tc4',
  tool: 'edit',
  args: {
    'path': 'app/test/ui/chat/tool_request_card_test.dart',
    'hunks': [
      {
        'lines': [
          {'kind': 'context', 'oldLine': 16, 'newLine': 16, 'text': 'args: {'},
          {'kind': 'remove', 'oldLine': 17, 'text': "  tool: 'Edit',"},
          {'kind': 'add', 'newLine': 17, 'text': "  tool: 'edit',"},
          {'kind': 'context', 'oldLine': 18, 'newLine': 18, 'text': '},'},
        ],
      },
    ],
  },
);

void main() {
  testWidgets(
    'tools start collapsed, toggle exposes command and outcome; no approvals or shadow',
    (tester) async {
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: _bashTool)));
      expect(find.text('Bash'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.text('Running'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Deny'), findsNothing);
      final decoration = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(decoration.boxShadow, isNull);
      await tester.tap(find.byKey(const ValueKey('tool-toggle-tc1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-toggle-tc1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SelectableText), findsNothing);
    },
  );

  testWidgets(
    'expanded edit retains rich diff context, added and removed lines',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const ToolRequestCard(tool: _editToolWithHunk)),
      );
      await tester.tap(find.byKey(const ValueKey('tool-toggle-tc2')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('   16 args: {', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining("-  17   tool: 'Edit',", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining("+  17   tool: 'edit',", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('   18 },', findRichText: true),
        findsOneWidget,
      );
    },
  );

  for (final status in ToolEventStatus.values) {
    testWidgets('$status collapse rule and status glyph', (tester) async {
      final tool = _bashTool.copyWith(
        status: status,
        error: status == ToolEventStatus.failed ? 'exit 1' : null,
      );
      await tester.pumpWidget(_wrap(ToolRequestCard(tool: tool)));
      expect(
        find.byType(SelectableText),
        status == ToolEventStatus.failed ? findsOneWidget : findsNothing,
      );
      if (status == ToolEventStatus.failed) {
        final text = tester.widget<Text>(find.text('exit 1'));
        expect(text.style?.color, AppColors.dark.error);
      }
    });
  }

  testWidgets('failure arriving on a collapsed card auto-expands it', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ToolRequestCard(tool: _bashTool)));
    await tester.pumpWidget(
      _wrap(
        ToolRequestCard(
          tool: _bashTool.copyWith(
            status: ToolEventStatus.failed,
            error: 'failed',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('failed'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('output is limited to 12 lines until Show all', (tester) async {
    final output = List.generate(15, (i) => 'line $i').join('\n');
    await tester.pumpWidget(
      _wrap(
        ToolRequestCard(
          tool: _bashTool.copyWith(
            status: ToolEventStatus.completed,
            result: output,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tool-toggle-tc1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('line 14'), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text(output), findsOneWidget);
  });

  for (final count in [3, 4, 5]) {
    testWidgets('$count consecutive tools grouping threshold', (tester) async {
      final tools = List.generate(
        count,
        (i) => ToolEvent(
          id: '$i',
          toolCallId: '$i',
          tool: 'bash',
          args: {'command': 'ls $i'},
          status: ToolEventStatus.completed,
        ),
      );
      await tester.pumpWidget(_wrap(ToolCallGroup(tools: tools)));
      expect(
        find.byType(ToolRequestCard),
        count > 3 ? findsNothing : findsNWidgets(count),
      );
      if (count > 3) {
        expect(find.text('$count tool calls'), findsOneWidget);
        await tester.tap(find.text('$count tool calls'));
        await tester.pumpAndSettle();
        expect(find.byType(ToolRequestCard), findsNWidgets(count));
      }
    });
  }
  testWidgets(
    'failed tool stays visible and expanded in a collapsed large group',
    (tester) async {
      final tools = List.generate(
        5,
        (i) => ToolEvent(
          id: '$i',
          toolCallId: '$i',
          tool: 'bash',
          args: {'command': 'ls'},
          status: i == 2 ? ToolEventStatus.failed : ToolEventStatus.completed,
          error: i == 2 ? 'permission denied' : null,
        ),
      );
      await tester.pumpWidget(_wrap(ToolCallGroup(tools: tools)));
      expect(find.text('5 tool calls'), findsOneWidget);
      expect(find.byType(ToolRequestCard), findsOneWidget);
      expect(find.text('permission denied'), findsOneWidget);
      await tester.tap(find.text('5 tool calls'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolRequestCard), findsNWidgets(5));
    },
  );
}
