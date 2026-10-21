import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';

/// Preserve the existing post/composer layouts while sharing Android appearance.
abstract final class PostTheme {
  static const background = HhTelegramPalette.lightCard;
  static const surface = Color(0xFFFFFFFF);
  static const ink = HhTelegramPalette.lightInk;
  static const cardTint = HhTelegramPalette.lightCard;
  static const failure = Color(0xFFFF1646);
  static const destructive = Color(0xFFE42A22);
  static const errorInk = Color(0xFFB3261E);
  // Platform font fallback only; actual native CJK font availability is device acceptance.
  static const dialogQuestion = TextStyle(
    fontFamily: 'Roboto',
    fontFamilyFallback: ['HhNotoSansSC'],
    fontSize: 18,
    height: 1.5,
    color: ink,
  );
  static const dialogBody = TextStyle(
    fontFamily: 'Roboto',
    fontFamilyFallback: ['HhNotoSansSC'],
    fontSize: 15,
    height: 1.6,
    color: muted,
  );
  static const muted = HhTelegramPalette.lightSecondary;
  static const accent = HhTelegramPalette.lightAccent;
  static const line = HhTelegramPalette.lightLine;

  static ThemeData of(BuildContext context) {
    final base = HhTelegramTheme.applyAppearance(
      Theme.of(context).copyWith(
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(),
      ),
    );
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: surface,
        secondary: accent,
        onSecondary: surface,
        surface: surface,
        onSurface: ink,
        error: errorInk,
        onError: surface,
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      iconTheme: const IconThemeData(color: muted),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        shape: const Border(bottom: BorderSide(color: line)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HhTelegramPalette.lightAction,
          foregroundColor: surface,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
