import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('press scales down, releases, and respects reduced motion', (
    tester,
  ) async {
    var taps = 0;
    Future<void> show(bool reduced) => tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: Center(
              child: PrimaryButton(label: 'Pair', onPressed: () => taps++),
            ),
          ),
        ),
      ),
    );
    await show(false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pair')),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .97);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await show(true);
    final reducedGesture = await tester.startGesture(
      tester.getCenter(find.text('Pair')),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await reducedGesture.cancel();
  });
}
