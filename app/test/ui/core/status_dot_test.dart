import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: buildLightTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final (status, label) in [
    (AgentStatus.working, 'Working'),
    (AgentStatus.online, 'Online'),
    (AgentStatus.offline, 'Offline'),
    (AgentStatus.checking, 'Checking'),
    (AgentStatus.unknown, 'Checking'),
    (AgentStatus.stale, 'Last known: Working'),
  ]) {
    testWidgets('$status exposes "$label"', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(StatusDot(status: status)));
      expect(find.bySemanticsLabel(label), findsOneWidget);
      if (status == AgentStatus.stale) {
        expect(
          find.descendant(
            of: find.byType(StatusDot),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      } else {
        final dot = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(StatusDot),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = dot.decoration! as BoxDecoration;
        if (status == AgentStatus.working || status == AgentStatus.online) {
          expect(
            decoration.color,
            status == AgentStatus.working
                ? AppColors.light.working
                : AppColors.light.online,
          );
          expect(decoration.border, isNull);
        } else {
          expect(decoration.color, isNull);
          expect(
            decoration.border,
            Border.all(
              color:
                  status == AgentStatus.checking ||
                      status == AgentStatus.unknown
                  ? AppColors.light.accent
                  : AppColors.light.ink2,
              width: 1.5,
            ),
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });
  }

  testWidgets('stale preserves the last known status in semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const StatusDot(
          status: AgentStatus.stale,
          lastKnownStatus: AgentStatus.online,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Last known: Online'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('working pulses, reduced motion and other states stay static', (
    tester,
  ) async {
    await tester.pumpWidget(host(const StatusDot(status: AgentStatus.working)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(StatusDot),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .storage[0],
      greaterThan(1),
    );
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(
      host(const StatusDot(status: AgentStatus.working), reduceMotion: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(StatusDot),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .storage[0],
      1,
    );
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(host(const StatusDot(status: AgentStatus.offline)));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('checking dims the ring to half opacity', (tester) async {
    await tester.pumpWidget(
      host(const StatusDot(status: AgentStatus.checking)),
    );
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(StatusDot),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, .5);
  });
}
