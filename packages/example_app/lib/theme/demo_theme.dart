import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Party-game palette — saturated toys, not soft editorial paper.
abstract final class DemoColors {
  static const ink = Color(0xFF1F2430);
  static const coral = Color(0xFFFF5A5F);
  static const teal = Color(0xFF1DB8A0);
  static const gold = Color(0xFFFFC043);
  static const paperTop = Color(0xFFFFF6E8);
  static const paperBottom = Color(0xFFFFE8C8);
  static const card = Color(0xFFFFFCF5);
  static const muted = Color(0x991F2430);
  static const border = Color(0xFF1F2430);
}

/// Hard offset shadow — the GamePigeon / party-UI look (not soft Material blur).
List<BoxShadow> gameShadow({
  double dy = 5,
  double blur = 0,
  double alpha = 0.18,
  Color? color,
}) =>
    [
      BoxShadow(
        color: (color ?? DemoColors.ink).withValues(alpha: alpha),
        offset: Offset(0, dy),
        blurRadius: blur,
        spreadRadius: 0,
      ),
    ];

/// Chunky rounded display type (titles, buttons).
TextStyle gameDisplay({
  double size = 28,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double height = 1.05,
  double letterSpacing = -0.3,
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
  double height = 1.3,
}) =>
    GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color ?? DemoColors.ink.withValues(alpha: 0.65),
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
