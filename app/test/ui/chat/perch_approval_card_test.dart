import 'dart:convert';
import 'dart:io';

import 'package:app/domain/contracts/approval_client.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/widgets/perch_approval_card.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BoundApproval approval(Duration remaining) {
  final raw =
      (jsonDecode(
                File(
                  '../.orchestration/contracts/perch-v1/tool-approval.json',
                ).readAsStringSync(),
              )
              as Map)['request']
          as Map<String, dynamic>;
  return BoundApproval(
    request: PerchToolApprovalRequest.fromJson({
      ...raw,
      'expires_at': DateTime.now().add(remaining).millisecondsSinceEpoch,
    }),
    peerEpk: 'mac',
    roomId: 'room',
  );
}

Widget wrap(Widget child) => MaterialApp(
  theme: buildLightTheme(),
  home: Scaffold(body: child),
);
void main() {
  testWidgets('tool card expands args and Allow confirms with existing sheet', (
    tester,
  ) async {
    final decisions = <PerchApprovalDecision>[];
    await tester.pumpWidget(
      wrap(
        PerchApprovalCard(
          approval: approval(const Duration(minutes: 1)),
          onDecide: (d) async {
            decisions.add(d);
          },
        ),
      ),
    );
    expect(find.text('danger'), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    await tester.tap(find.text('danger'));
    await tester.pump();
    expect(find.textContaining('nested'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(decisions, isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Allow'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(decisions, [PerchApprovalDecision.allow]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Deny confirms and expired card disables both actions', (
    tester,
  ) async {
    final decisions = <PerchApprovalDecision>[];
    await tester.pumpWidget(
      wrap(
        PerchApprovalCard(
          approval: approval(const Duration(minutes: 1)),
          onDecide: (d) async {
            decisions.add(d);
          },
        ),
      ),
    );
    await tester.tap(find.text('Deny'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Deny'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(decisions, [PerchApprovalDecision.deny]);
    await tester.pumpWidget(
      wrap(
        PerchApprovalCard(
          key: const ValueKey('expired'),
          approval: approval(const Duration(seconds: -1)),
          onDecide: (d) async {
            decisions.add(d);
          },
        ),
      ),
    );
    expect(find.text('Expired'), findsOneWidget);
    for (final label in ['Allow', 'Deny']) {
      final button = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(button.onPressed, isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sheet cannot confirm an expired challenge', (tester) async {
    var sent = false;
    await tester.pumpWidget(
      wrap(
        PerchApprovalCard(
          approval: approval(const Duration(milliseconds: 250)),
          onDecide: (_) async {
            sent = true;
          },
        ),
      ),
    );
    await tester.tap(find.text('Allow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Wall clock drives authorization; this ensures an already expired sheet is inert.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Expired'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Allow'),
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(sent, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
  });
}
