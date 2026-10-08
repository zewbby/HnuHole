import 'package:flutter/material.dart';

/// 本片局部沿用已确认白色／灰蓝页面，不改变认证或全局主题。
abstract final class PostTheme {
  static const background = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF17212D);
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
      error: Color(0xFFB3261E),
      onError: surface,
    ),
    textTheme: Theme.of(context).textTheme
        .apply(bodyColor: ink, displayColor: ink),
    iconTheme: const IconThemeData(color: muted),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
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
