import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('wordmark loads bundled Fraunces 600 with networking disabled', (
    tester,
  ) async {
    final runtimeFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = runtimeFetching,
    );
    final style = brandTextStyle(fontSize: 34);
    await tester.runAsync(() => GoogleFonts.pendingFonts());
    expect(style.fontFamily, startsWith('Fraunces'));
    expect(style.fontWeight, FontWeight.w600);
    expect(kMonoFamily, 'JetBrainsMono');
    expect(AppTypography.light.body.fontSize, 17);
    expect(AppTypography.light.mono.fontSize, 14);
    expect(AppTypography.light.body.fontFamily, isNull);
  });
}
