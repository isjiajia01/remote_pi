// Plan/32 — the compaction system bubble renders the label, the recap summary
// and the reclaimed token count (distinct from user/assistant bubbles).

import 'package:app/domain/session_state.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/ui/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, CompactionMsg msg) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CompactionBubble(msg))),
    );
  }

  testWidgets('shows label + summary + token count', (tester) async {
    await pump(
      tester,
      const CompactionMsg(
        id: 'c1',
        summary: 'Recapped the long thread',
        tokensBefore: 12000,
      ),
    );

    expect(find.text('Context compacted'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Recapped the long thread'), findsOneWidget);
    expect(find.text('~12000 tokens'), findsOneWidget);
  });

  testWidgets('omits the token line when tokensBefore is null', (tester) async {
    await pump(tester, const CompactionMsg(id: 'c2', summary: 'done'));

    expect(find.text('Context compacted'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('done'), findsOneWidget);
    expect(find.textContaining('tokens'), findsNothing);
  });
  testWidgets('persisted compaction timestamp reaches the divider', (
    tester,
  ) async {
    final record = MessageRecord(
      id: 'c3',
      seq: 1,
      role: MsgRole.compaction,
      ts: DateTime(2026, 10, 12, 14, 2),
    );
    final msg = record.toChatMessage() as CompactionMsg;
    expect(msg.timestamp, record.ts);
    await pump(tester, msg);
    expect(find.text('Context compacted · 14:02'), findsOneWidget);
  });
}
