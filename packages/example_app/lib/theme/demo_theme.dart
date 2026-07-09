import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Soft party palette — playful color, low visual noise.
abstract final class DemoColors {
  static const ink = Color(0xFF2A3140);
  static const coral = Color(0xFFFF6B6B);
  static const teal = Color(0xFF2EC4B6);
  static const gold = Color(0xFFFFC857);
  static const paperTop = Color(0xFFFFF8EF);
  static const paperBottom = Color(0xFFFFEBD0);
  static const card = Color(0xFFFFFDF9);
  static const muted = Color(0x992A3140);
  /// Soft outline — never a hard black stamp.
  static const border = Color(0x332A3140);
}

/// Layered soft shadow: a bit of depth without the harsh sticker look.
List<BoxShadow> gameShadow({
  double dy = 10,
  double blur = 22,
  double alpha = 0.10,
  Color? color,
  double accentAlpha = 0.0,
  Color? accent,
}) =>
    [
      BoxShadow(
        color: (color ?? DemoColors.ink).withValues(alpha: alpha),
        offset: Offset(0, dy),
        blurRadius: blur,
        spreadRadius: -2,
      ),
      if (accentAlpha > 0 && accent != null)
        BoxShadow(
          color: accent.withValues(alpha: accentAlpha),
          offset: Offset(0, dy * 0.4),
          blurRadius: blur * 1.2,
          spreadRadius: 0,
        ),
    ];

/// Rounded display type (titles, buttons).
TextStyle gameDisplay({
  double size = 28,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double height = 1.05,
  double letterSpacing = -0.2,
}) =>
    GoogleFonts.fredoka(
      fontSize: size,
      fontWeight: weight,
      color: color ?? DemoColors.ink,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Friendly body type.
TextStyle gameBody({
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double height = 1.35,
}) =>
    GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color ?? DemoColors.ink.withValues(alpha: 0.58),
      height: height,
    );

ThemeData buildDemoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DemoColors.coral,
    brightness: Brightness.light,
  ).copyWith(
    surface: DemoColors.card,
    tertiary: DemoColors.teal,
    onSurface: DemoColors.ink,
    primary: DemoColors.coral,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final display = GoogleFonts.fredokaTextTheme(base.textTheme);
  final body = GoogleFonts.nunitoTextTheme(base.textTheme);

  return base.copyWith(
    scaffoldBackgroundColor: DemoColors.paperTop,
    textTheme: display
        .copyWith(
          bodyLarge: body.bodyLarge,
          bodyMedium: body.bodyMedium,
          bodySmall: body.bodySmall,
          labelLarge: body.labelLarge,
          labelMedium: body.labelMedium,
          labelSmall: body.labelSmall,
          titleMedium: body.titleMedium,
          titleSmall: body.titleSmall,
        )
        .apply(bodyColor: DemoColors.ink, displayColor: DemoColors.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: DemoColors.ink,
      titleTextStyle: gameDisplay(size: 20),
    ),
  );
}
