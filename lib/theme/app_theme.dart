import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

final class AppTheme {
  const AppTheme._();

  static ThemeData light(AppConfig config, Color primary) => _build(
    config: config,
    primary: primary,
    brightness: Brightness.light,
    background: const Color(0xFFF4F7F5),
    surface: Colors.white,
  );

  static ThemeData dark(AppConfig config, Color primary) => _build(
    config: config,
    primary: primary,
    brightness: Brightness.dark,
    background: const Color(0xFF061514),
    surface: const Color(0xFF0B2220),
  );

  static ThemeData _build({
    required AppConfig config,
    required Color primary,
    required Brightness brightness,
    required Color background,
    required Color surface,
  }) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      secondary: Color(config.theme.secondary),
      surface: surface,
      brightness: brightness,
    );
    final TextTheme base = ThemeData(
      brightness: brightness,
    ).textTheme.apply(fontFamily: 'Atkinson');
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(
          fontFamily: 'Newsreader',
          fontWeight: FontWeight.w700,
          height: 0.98,
        ),
        displayMedium: base.displayMedium?.copyWith(
          fontFamily: 'Newsreader',
          fontWeight: FontWeight.w600,
          height: 1.02,
        ),
        headlineLarge: base.headlineLarge?.copyWith(
          fontFamily: 'Newsreader',
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          fontFamily: 'Newsreader',
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(config.theme.radius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.theme.radius * 0.7),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.theme.radius * 0.7),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(config.theme.radius * 0.7),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(config.theme.radius * 0.7),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
