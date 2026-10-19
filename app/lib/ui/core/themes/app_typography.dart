import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/ui/core/themes/app_colors.dart';

/// Bundled machine-data font. Prose and chrome use the platform system font.
const String kMonoFamily = 'JetBrainsMono';
const String? kSansFamily = null;

/// Fraunces wordmark, loaded by google_fonts from the bundled 600 asset.
/// The legacy weight argument remains accepted while screens migrate; the
/// wordmark always uses the design's single 600 weight.
TextStyle brandTextStyle({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.fraunces(
  fontSize: fontSize,
  fontWeight: FontWeight.w600,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// Design scale. Dynamic Type is applied above the router by app_font_scale.
/// Use [tabularFigures] for count and time labels.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.largeTitle,
    required this.title2,
    required this.headline,
    required this.body,
    required this.chatBody,
    required this.subhead,
    required this.footnote,
    required this.caption,
    required this.sectionLabel,
    required this.mono,
    required this.monoSmall,
    required this.monoCode,
  });

  final TextStyle largeTitle;
  final TextStyle title2;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle chatBody;
  final TextStyle subhead;
  final TextStyle footnote;
  final TextStyle caption;
  final TextStyle sectionLabel;
  final TextStyle mono;
  final TextStyle monoSmall;
  final TextStyle monoCode;

  TextStyle get sansBody => body;
  static const tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

  factory AppTypography.fromColors(AppColors c) => AppTypography(
    largeTitle: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 34,
      height: 41 / 34,
      fontWeight: FontWeight.w700,
      color: c.ink,
    ),
    title2: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    headline: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    body: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w400,
      color: c.ink,
    ),
    chatBody: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 16,
      height: 23 / 16,
      fontWeight: FontWeight.w400,
      color: c.ink,
    ),
    subhead: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w400,
      color: c.ink,
    ),
    footnote: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
      color: c.ink,
    ),
    caption: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      color: c.ink,
      letterSpacing: 0.2,
    ),
    sectionLabel: TextStyle(
      fontFamily: kSansFamily,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
      color: c.ink2,
      letterSpacing: 0.6,
    ),
    mono: TextStyle(
      fontFamily: kMonoFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      color: c.ink,
    ),
    monoSmall: TextStyle(
      fontFamily: kMonoFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      color: c.ink2,
    ),
    monoCode: TextStyle(
      fontFamily: kMonoFamily,
      fontSize: 13,
      height: 19 / 13,
      fontWeight: FontWeight.w400,
      color: c.codeInk,
    ),
  );

  static final dark = AppTypography.fromColors(AppColors.dark);
  static final light = AppTypography.fromColors(AppColors.light);

  @override
  AppTypography copyWith({
    TextStyle? largeTitle,
    TextStyle? title2,
    TextStyle? headline,
    TextStyle? body,
    TextStyle? chatBody,
    TextStyle? subhead,
    TextStyle? footnote,
    TextStyle? caption,
    TextStyle? sectionLabel,
    TextStyle? mono,
    TextStyle? monoSmall,
    TextStyle? monoCode,
  }) => AppTypography(
    largeTitle: largeTitle ?? this.largeTitle,
    title2: title2 ?? this.title2,
    headline: headline ?? this.headline,
    body: body ?? this.body,
    chatBody: chatBody ?? this.chatBody,
    subhead: subhead ?? this.subhead,
    footnote: footnote ?? this.footnote,
    caption: caption ?? this.caption,
    sectionLabel: sectionLabel ?? this.sectionLabel,
    mono: mono ?? this.mono,
    monoSmall: monoSmall ?? this.monoSmall,
    monoCode: monoCode ?? this.monoCode,
  );

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      largeTitle: TextStyle.lerp(largeTitle, other.largeTitle, t)!,
      title2: TextStyle.lerp(title2, other.title2, t)!,
      headline: TextStyle.lerp(headline, other.headline, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      chatBody: TextStyle.lerp(chatBody, other.chatBody, t)!,
      subhead: TextStyle.lerp(subhead, other.subhead, t)!,
      footnote: TextStyle.lerp(footnote, other.footnote, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
      monoCode: TextStyle.lerp(monoCode, other.monoCode, t)!,
    );
  }
}
