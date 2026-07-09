import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GamePigeon-adjacent shell palette: quiet iOS light surface, color only
/// on tiles and in-game pieces. The chrome stays out of the way so this can
/// later drop into a chat sheet without fighting the host app's look.
abstract final class DemoColors {
  static const ink = Color(0xFF1C1C1E);
  static const secondaryLabel = Color(0x993C3C43);
  static const tertiaryLabel = Color(0x4D3C3C43);
  static const surface = Color(0xFFF2F2F7);
  static const card = Color(0xFFFFFFFF);
  static const separator = Color(0x1A3C3C43);

  // Game accents (used on tiles + boards, not shell chrome).
  static const coral = Color(0xFFFF3B30);
  static const teal = Color(0xFF34C759);
  static const gold = Color(0xFFFFCC00);
  static const blue = Color(0xFF007AFF);

  // Legacy aliases used by play screens / board styles.
  static const paperTop = surface;
  static const paperBottom = surface;
  static const muted = secondaryLabel;
  static const border = separator;
}

/// Soft depth only — no hard sticker shadows.
List<BoxShadow> gameShadow({
  double dy = 4,
  double blur = 12,
  double alpha = 0.08,
  Color? color,
  double accentAlpha = 0,
  Color? accent,
}) =>
    [
      BoxShadow(
        color: (color ?? Colors.black).withValues(alpha: alpha),
        offset: Offset(0, dy),
        blurRadius: blur,
        spreadRadius: 0,
      ),
    ];

/// Quiet labels (launcher captions, chrome).
TextStyle gameBody({
  double size = 13,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double height = 1.2,
}) =>
    GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color ?? DemoColors.secondaryLabel,
      height: height,
    );

/// Slightly stronger titles inside games — still not loud arcade display.
TextStyle gameDisplay({
  double size = 22,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double height = 1.1,
  double letterSpacing = -0.2,
}) =>
    GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color ?? DemoColors.ink,
      height: height,
      letterSpacing: letterSpacing,
    );

ThemeData buildDemoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DemoColors.blue,
    brightness: Brightness.light,
  ).copyWith(
    surface: DemoColors.surface,
    onSurface: DemoColors.ink,
    primary: DemoColors.blue,
    tertiary: DemoColors.teal,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = GoogleFonts.nunitoTextTheme(base.textTheme);

  return base.copyWith(
    scaffoldBackgroundColor: DemoColors.surface,
    textTheme: text.apply(
      bodyColor: DemoColors.ink,
      displayColor: DemoColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: DemoColors.card,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: DemoColors.ink,
      titleTextStyle: gameDisplay(size: 17, weight: FontWeight.w700),
    ),
  );
}
