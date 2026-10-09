import 'package:flutter/material.dart';

/// 本片局部沿用已确认白色／灰蓝页面，不改变认证或全局主题。
abstract final class PostTheme {
  static const background = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF11151A);
  static const cardTint = Color(0xFFE9ECF0);
  static const failure = Color(0xFFFF1646);
  static const destructive = Color(0xFFE42A22);
  static const errorInk = Color(0xFFB3261E);
  // Platform font fallback only; actual native CJK font availability is device acceptance.
  static const dialogQuestion = TextStyle(
    fontFamily: 'SimSun',
    fontFamilyFallback: ['Songti SC', 'Noto Serif CJK SC', 'serif'],
    fontSize: 18,
    height: 1.5,
    color: ink,
  );
  static const dialogBody = TextStyle(
    fontFamily: 'SimSun',
    fontFamilyFallback: ['Songti SC', 'Noto Serif CJK SC', 'serif'],
    fontSize: 15,
    height: 1.6,
    color: muted,
  );
  static const muted = Color(0xFF58677C);
  static const accent = Color(0xFF304B67);
  static const line = Color(0xFFDFE4EA);

  static ThemeData of(BuildContext context) => Theme.of(context).copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: surface,
    colorScheme: const ColorScheme.light(
      primary: accent,
      onPrimary: surface,
      secondary: muted,
      onSecondary: surface,
      surface: surface,
      onSurface: ink,
      error: errorInk,
      onError: surface,
    ),
    textTheme: Theme.of(context).textTheme
        .apply(bodyColor: ink, displayColor: ink),
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
      titleTextStyle: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
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
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}
