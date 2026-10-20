import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/message_list.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final messages = List.generate(
    40,
    (i) => AssistantMsg(
      id: '$i',
      text: 'Turn $i.\nAn agent response with some output.',
    ),
  );
  Future<void> pump(
    WidgetTester tester, {
    StreamingMessage? streaming,
    List<ChatMessage>? history,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageList(
          messages: history ?? messages,
          streaming: streaming,
          answeredQuestions: const [],
          onRetry: (_) {},
          onDecide: (_, _) {},
        ),
      ),
    ),
  );

  testWidgets(
    'follows output within 120pt; reading older turns keeps position and offers New output',
    (tester) async {
      await pump(tester);
      final list = find.byType(ListView);
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.offset, 0);
      controller.jumpTo(80);
      await pump(
        tester,
        streaming: const StreamingMessage(inReplyTo: 'u', buffer: 'First'),
      );
      await tester.pump();
      expect(controller.offset, 0);
      controller.jumpTo(400);
      await tester.pump();
      await pump(
        tester,
        streaming: const StreamingMessage(
          inReplyTo: 'u',
          buffer: 'First and more',
        ),
      );
      await tester.pump();
      expect(controller.offset, 400);
      expect(find.text('↓ New output'), findsOneWidget);
      await tester.tap(find.text('↓ New output'));
      await tester.pump();
      expect(controller.offset, 0);
      expect(find.text('↓ New output'), findsNothing);
    },
  );

  testWidgets('a user or assistant turn separates tool groups', (tester) async {
    final tools = List.generate(
      5,
      (i) => ToolEvent(
        id: 't$i',
        toolCallId: '$i',
        tool: 'bash',
        args: {'command': 'echo $i'},
        status: ToolEventStatus.completed,
      ),
    );
    await pump(
      tester,
      history: [
        tools[0],
        tools[1],
        const AssistantMsg(id: 'a', text: 'Continuing'),
        ...tools.skip(2),
      ],
    );
    expect(find.byType(ToolCallGroup), findsNWidgets(2));
    expect(find.textContaining('tool calls'), findsNothing);
    expect(find.byType(ToolRequestCard), findsNWidgets(5));
  });
}
