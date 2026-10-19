import 'package:flutter/material.dart';

/// Perch's light and dark semantic palette, defined in docs/DESIGN.md.
/// Widgets consume these tokens through `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.hairline,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.onAccent,
    required this.working,
    required this.workingSoft,
    required this.online,
    required this.error,
    required this.errorSoft,
    required this.userBubble,
    required this.codeInk,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color hairline;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color accent;
  final Color onAccent;
  final Color working;
  final Color workingSoft;
  final Color online;
  final Color error;
  final Color errorSoft;
  final Color userBubble;
  final Color codeInk;

  // Compatibility aliases while screens migrate to the Phase 2 components.
  // Warnings stay neutral; amber is reserved for in-flight agent turns.
  Color get border => hairline;
  Color get text => ink;
  Color get muted => ink2;
  Color get muted2 => ink2;
  Color get highlight => codeInk;
  Color get success => online;
  Color get warning => ink2;
  Color get codeBg => surface2;
  Color get modelBadgeBg => surface2;
  Color get modelBadgeBorder => hairline;
  Color get denyBorder => hairline;
  Color get inputFill => surface2;

  static const AppColors light = AppColors(
    bg: Color(0xFFF4F2EC),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFECEAE3),
    hairline: Color(0xFFDAD7CE),
    ink: Color(0xFF1A1C1E),
    ink2: Color(0xFF5E6166),
    ink3: Color(0xFF85888D),
    accent: Color(0xFF1D5FC4),
    onAccent: Color(0xFFFFFFFF),
    working: Color(0xFFA65D00),
    workingSoft: Color(0xFFFBEBD3),
    online: Color(0xFF2F7D4F),
    error: Color(0xFFC2302B),
    errorSoft: Color(0xFFFBE3E1),
    userBubble: Color(0xFFE3E9F6),
    codeInk: Color(0xFF2B3A55),
  );

  static const AppColors dark = AppColors(
    bg: Color(0xFF0F1012),
    surface: Color(0xFF1A1C1F),
    surface2: Color(0xFF24272B),
    hairline: Color(0xFF2E3135),
    ink: Color(0xFFECEAE4),
    ink2: Color(0xFF9DA0A6),
    ink3: Color(0xFF6C7075),
    accent: Color(0xFF7FAEFF),
    onAccent: Color(0xFF0F1012),
    working: Color(0xFFF2A93B),
    workingSoft: Color(0xFF33270F),
    online: Color(0xFF5FC98A),
    error: Color(0xFFFF6B61),
    errorSoft: Color(0xFF3A1C1A),
    userBubble: Color(0xFF1E2A40),
    codeInk: Color(0xFFB9CCF0),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? hairline,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? accent,
    Color? onAccent,
    Color? working,
    Color? workingSoft,
    Color? online,
    Color? error,
    Color? errorSoft,
    Color? userBubble,
    Color? codeInk,
  }) => AppColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    hairline: hairline ?? this.hairline,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    ink3: ink3 ?? this.ink3,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    working: working ?? this.working,
    workingSoft: workingSoft ?? this.workingSoft,
    online: online ?? this.online,
    error: error ?? this.error,
    errorSoft: errorSoft ?? this.errorSoft,
    userBubble: userBubble ?? this.userBubble,
    codeInk: codeInk ?? this.codeInk,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      working: Color.lerp(working, other.working, t)!,
      workingSoft: Color.lerp(workingSoft, other.workingSoft, t)!,
      online: Color.lerp(online, other.online, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      codeInk: Color.lerp(codeInk, other.codeInk, t)!,
    );
  }
}
