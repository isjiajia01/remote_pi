import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  for (final dark in [false, true]) {
    for (final variant in BannerVariant.values) {
      testWidgets(
        '$variant uses the ${dark ? "dark" : "light"} palette and labels errors',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var retried = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? buildDarkTheme() : buildLightTheme(),
              home: Scaffold(
                body: AppBanner(
                  message: 'Relay offline',
                  variant: variant,
                  actionLabel: 'Retry',
                  onAction: () => retried = true,
                ),
              ),
            ),
          );
          final colors = dark ? AppColors.dark : AppColors.light;
          final error = variant == BannerVariant.error;
          final container = tester.widget<Container>(
            find.descendant(
              of: find.byType(AppBanner),
              matching: find.byType(Container),
            ),
          );
          expect(
            (container.decoration! as BoxDecoration).color,
            error ? colors.errorSoft : colors.surface2,
          );
          expect(tester.getSize(find.byWidget(container)).height, 44);
          expect(
            find.byIcon(error ? LucideIcons.circleAlert : LucideIcons.info),
            findsOneWidget,
          );
          expect(find.text('Relay offline'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('Relay offline')).style!.color,
            error ? colors.error : colors.ink,
          );
          await tester.tap(find.text('Retry'));
          expect(retried, isTrue);
          expect(
            find.bySemanticsLabel(RegExp('Relay offline')),
            findsOneWidget,
          );
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('visibility fades and settles with reduced motion', (
    tester,
  ) async {
    var visible = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: AppBanner(message: 'Connecting…', visible: visible),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Connecting…'), findsNothing);
    update(() => visible = true);
    await tester.pump();
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('Connecting…'), findsOneWidget);
    update(() => visible = false);
    await tester.pumpAndSettle();
    expect(find.text('Connecting…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
