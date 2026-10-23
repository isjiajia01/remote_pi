import 'package:app/ui/core/interaction_feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('feedback is throttled and silent while backgrounded', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    InteractionFeedback.selection();
    InteractionFeedback.action();
    await tester.pump();
    expect(calls.where((c) => c.method == 'HapticFeedback.vibrate').length, 1);
    expect(calls.first.arguments, 'HapticFeedbackType.selectionClick');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    InteractionFeedback.result();
    await tester.pump();
    expect(calls.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
