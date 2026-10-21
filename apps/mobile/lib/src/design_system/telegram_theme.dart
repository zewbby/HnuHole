import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared appearance calibrated against the user's Telegram Android screenshot.
/// JPEG samples are approximate; light text uses neutral grays rather than blue.
@immutable
class HhTelegramPalette extends ThemeExtension<HhTelegramPalette> {
  static const lightInk = Color(0xFF1D1D1D);
  static const lightSecondary = Color(0xFF757575);
  static const lightAccent = Color(0xFF168BDA);
  static const lightAction = Color(0xFF229AF0);
  static const lightLine = Color(0xFFEAEAEA);
  static const lightCard = Color(0xFFF1F1F3);
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
    ink: lightInk,
    secondary: lightSecondary,
    accent: lightAccent,
    action: lightAction,
    onAccent: Color(0xFFFFFFFF),
    outgoingTime: Color(0xFF486D3F),
    line: lightLine,
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
  static bool _licensesRegistered = false;
  static void registerFontLicenses() {
    if (_licensesRegistered) return;
    _licensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        ['Roboto'],
        '${await rootBundle.loadString('assets/fonts/NOTICE-Roboto.txt')}\n${await rootBundle.loadString('assets/fonts/LICENSE-Roboto.txt')}',
      );
      yield LicenseEntryWithLineBreaks([
        'Noto Sans SC',
      ], await rootBundle.loadString('assets/fonts/OFL-NotoSansSC.txt'));
    });
  }

  /// Change fonts and semantic colors without changing existing component sizes,
  /// padding, radii, routes, or the page's text scale and explicit type sizes.
  static ThemeData applyAppearance(ThemeData base, {String? fontFamily}) {
    final colors = base.brightness == Brightness.dark
        ? HhTelegramPalette.dark
        : HhTelegramPalette.light;
    final family = fontFamily ?? 'Roboto';
    const fallback = ['HhNotoSansSC'];
    final text = base.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
      bodyColor: colors.ink,
      displayColor: colors.ink,
    );
    final scheme = base.colorScheme.copyWith(
      primary: colors.accent,
      onPrimary: colors.onAccent,
      primaryContainer: colors.selection,
      onPrimaryContainer: colors.ink,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      secondaryContainer: colors.selection,
      onSecondaryContainer: colors.ink,
      tertiary: colors.accent,
      onTertiary: colors.onAccent,
      tertiaryContainer: colors.selection,
      onTertiaryContainer: colors.ink,
      surface: colors.surface,
      surfaceDim: colors.background,
      surfaceBright: colors.surface,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.background,
      surfaceContainer: colors.background,
      surfaceContainerHigh: colors.background,
      surfaceContainerHighest: colors.background,
      onSurface: colors.ink,
      onSurfaceVariant: colors.secondary,
      outline: colors.secondary,
      outlineVariant: colors.line,
      surfaceTint: Colors.transparent,
      error: colors.error,
      inverseSurface: const Color(0xFF363F46),
      onInverseSurface: Colors.white,
      inversePrimary: HhTelegramPalette.dark.accent,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      cardColor: colors.surface,
      dividerColor: colors.line,
      disabledColor: colors.secondary.withValues(alpha: .5),
      textTheme: text,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
      extensions: [
        ...base.extensions.values.where((value) => value is! HhTelegramPalette),
        colors,
      ],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: colors.header,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: base.iconTheme.copyWith(color: colors.secondary),
      iconButtonTheme: IconButtonThemeData(
        style: (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStatePropertyAll(colors.secondary),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: text.bodyLarge?.copyWith(color: colors.secondary),
        labelStyle: text.bodyLarge?.copyWith(color: colors.secondary),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.action,
        selectionColor: colors.action.withValues(alpha: .22),
        selectionHandleColor: colors.action,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.action.withValues(alpha: .14)
                : colors.action,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.secondary
                : Colors.white,
          ),
          textStyle: WidgetStatePropertyAll(
            text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.secondary
                : colors.accent,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.secondary
                : colors.accent,
          ),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: colors.action,
        foregroundColor: Colors.white,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: colors.raised,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: colors.raised,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: colors.raised,
        surfaceTintColor: Colors.transparent,
        textStyle: (base.popupMenuTheme.textStyle ?? text.bodyLarge)?.copyWith(
          color: colors.ink,
          fontFamily: family,
          fontFamilyFallback: fallback,
        ),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: colors.line),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: HhTelegramPalette.dark.accent,
      ),
    );
  }

  static ThemeData create(Brightness brightness, {String? fontFamily}) {
    final colors = brightness == Brightness.dark
        ? HhTelegramPalette.dark
        : HhTelegramPalette.light;
    return applyAppearance(
      ThemeData(
        useMaterial3: true,
        brightness: brightness,
        fontFamily: fontFamily ?? 'Roboto',
        fontFamilyFallback: const ['HhNotoSansSC'],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: colors.line,
          space: 1,
          thickness: 1,
        ),
      ),
      fontFamily: fontFamily,
    );
  }
}
