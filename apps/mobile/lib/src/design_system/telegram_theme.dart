import 'package:flutter/material.dart';

/// Telegram Android base light colors and bundled Dark Blue theme.
/// Secondary/time text use contrast-adjusted values; see telegram-colors.md.
/// The existing app root may adopt this theme one feature at a time.
@immutable
class HhTelegramPalette extends ThemeExtension<HhTelegramPalette> {
  const HhTelegramPalette({
    required this.background,
    required this.surface,
    required this.header,
    required this.raised,
    required this.incoming,
    required this.outgoing,
    required this.ink,
    required this.secondary,
    required this.accent,
    required this.action,
    required this.onAccent,
    required this.outgoingTime,
    required this.line,
    required this.error,
    required this.selection,
  });

  static const light = HhTelegramPalette(
    background: Color(0xFFF1F1F3),
    surface: Color(0xFFFFFFFF),
    header: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    incoming: Color(0xFFFFFFFF),
    outgoing: Color(0xFFEFFFDE),
    ink: Color(0xFF1A1D21),
    secondary: Color(0xFF566876),
    accent: Color(0xFF2678B6),
    action: Color(0xFF229AF0),
    onAccent: Color(0xFFFFFFFF),
    outgoingTime: Color(0xFF486D3F),
    line: Color(0xFFD9D9D9),
    error: Color(0xFFCC2929),
    selection: Color(0xFFECF7FD),
  );
  static const dark = HhTelegramPalette(
    background: Color(0xFF151E27),
    surface: Color(0xFF1D2733),
    header: Color(0xFF242D39),
    raised: Color(0xFF212D3B),
    incoming: Color(0xFF232E3B),
    outgoing: Color(0xFF3E618A),
    ink: Color(0xFFFAFAFA),
    secondary: Color(0xFFA1B2C2),
    accent: Color(0xFF64B5EF),
    action: Color(0xFF229AF0),
    onAccent: Color(0xFF10283D),
    outgoingTime: Color(0xFFD2E6F7),
    line: Color(0xFF2B3B4B),
    error: Color(0xFFEE686F),
    selection: Color(0xFF314A61),
  );

  final Color background, surface, header, raised, incoming, outgoing, ink;
  final Color secondary,
      accent,
      action,
      onAccent,
      outgoingTime,
      line,
      error,
      selection;

  static HhTelegramPalette of(BuildContext context) =>
      Theme.of(context).extension<HhTelegramPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  HhTelegramPalette copyWith({
    Color? background,
    Color? surface,
    Color? header,
    Color? raised,
    Color? incoming,
    Color? outgoing,
    Color? ink,
    Color? secondary,
    Color? accent,
    Color? action,
    Color? onAccent,
    Color? outgoingTime,
    Color? line,
    Color? error,
    Color? selection,
  }) => HhTelegramPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    header: header ?? this.header,
    raised: raised ?? this.raised,
    incoming: incoming ?? this.incoming,
    outgoing: outgoing ?? this.outgoing,
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    accent: accent ?? this.accent,
    action: action ?? this.action,
    onAccent: onAccent ?? this.onAccent,
    outgoingTime: outgoingTime ?? this.outgoingTime,
    line: line ?? this.line,
    error: error ?? this.error,
    selection: selection ?? this.selection,
  );

  @override
  HhTelegramPalette lerp(covariant HhTelegramPalette? other, double t) {
    if (other == null) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return HhTelegramPalette(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      header: blend(header, other.header),
      raised: blend(raised, other.raised),
      incoming: blend(incoming, other.incoming),
      outgoing: blend(outgoing, other.outgoing),
      ink: blend(ink, other.ink),
      secondary: blend(secondary, other.secondary),
      accent: blend(accent, other.accent),
      action: blend(action, other.action),
      onAccent: blend(onAccent, other.onAccent),
      outgoingTime: blend(outgoingTime, other.outgoingTime),
      line: blend(line, other.line),
      error: blend(error, other.error),
      selection: blend(selection, other.selection),
    );
  }
}

abstract final class HhTelegramTheme {
  static ThemeData create(Brightness brightness, {String? fontFamily}) {
    final colors = brightness == Brightness.dark
        ? HhTelegramPalette.dark
        : HhTelegramPalette.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily ?? 'Roboto',
      fontFamilyFallback: const ['Noto Sans CJK SC'],
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: colors.accent,
            brightness: brightness,
          ).copyWith(
            primary: colors.accent,
            onPrimary: colors.onAccent,
            surface: colors.surface,
            onSurface: colors.ink,
            error: colors.error,
            onSurfaceVariant: colors.secondary,
            outlineVariant: colors.line,
          ),
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.header,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 56,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.secondary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(color: colors.ink, fontSize: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.raised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
