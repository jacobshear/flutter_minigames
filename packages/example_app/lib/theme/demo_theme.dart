import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warm editorial palette for the standalone demo app.
/// Injected into each game's style so the catalog feels like one product.
abstract final class DemoColors {
  static const ink = Color(0xFF2E2A26);
  static const coral = Color(0xFFEE5D50);
  static const teal = Color(0xFF14A08D);
  static const paperTop = Color(0xFFFBF5EA);
  static const paperBottom = Color(0xFFF1E4CF);
  static const card = Color(0xFFFFFDF8);
  static const muted = Color(0x992E2A26);
}

ThemeData buildDemoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DemoColors.coral,
    brightness: Brightness.light,
  ).copyWith(
    surface: DemoColors.card,
    tertiary: DemoColors.teal,
    onSurface: DemoColors.ink,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: DemoColors.paperTop,
    textTheme: GoogleFonts.frauncesTextTheme(base.textTheme).apply(
      bodyColor: DemoColors.ink,
      displayColor: DemoColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: DemoColors.ink,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: DemoColors.ink,
      ),
    ),
  );
}
