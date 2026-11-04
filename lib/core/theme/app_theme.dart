import 'package:flutter/material.dart';

/// "Field instrument" palette shared with the desktop app.
class Accent {
  static const a300 = Color(0xFF62DBBF);
  static const a400 = Color(0xFF2FC3A5);
  static const a500 = Color(0xFF13A68B);
  static const a600 = Color(0xFF0B8672);
  static const a700 = Color(0xFF0D6B5C);
}

class Neutral {
  static const n50 = Color(0xFFF5F7F6);
  static const n100 = Color(0xFFEAEEEC);
  static const n200 = Color(0xFFD6DDDA);
  static const n300 = Color(0xFFB5C0BC);
  static const n400 = Color(0xFF8B9893);
  static const n500 = Color(0xFF67746F);
  static const n600 = Color(0xFF4E5954);
  static const n700 = Color(0xFF39433F);
  static const n800 = Color(0xFF252D2A);
  static const n850 = Color(0xFF1C2220);
  static const n900 = Color(0xFF151A18);
  static const n925 = Color(0xFF111513);
  static const n950 = Color(0xFF0C0F0E);
}

const String monoFamily = 'monospace';
/// Corner radius; rounder than the desktop's (3–6 px) for touch.
const double radius = 8;

TextStyle mono(BuildContext context, {double? size, Color? color, FontWeight? weight}) =>
    TextStyle(
      fontFamily: monoFamily,
      fontSize: size ?? 12.5,
      color: color,
      fontWeight: weight,
      height: 1.4,
    );

/// Small uppercase mono label (the desktop's `.eyebrow`).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: monoFamily,
          fontSize: 10.5,
          letterSpacing: 1.2,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? Accent.a400 : Accent.a600,
    onPrimary: dark ? Neutral.n950 : Colors.white,
    primaryContainer: dark ? Accent.a700 : Accent.a300,
    onPrimaryContainer: dark ? Neutral.n50 : Neutral.n950,
    secondary: dark ? Accent.a300 : Accent.a700,
    onSecondary: dark ? Neutral.n950 : Colors.white,
    error: dark ? const Color(0xFFF08A7E) : const Color(0xFFB3382C),
    onError: dark ? Neutral.n950 : Colors.white,
    surface: dark ? Neutral.n925 : Neutral.n50,
    onSurface: dark ? Neutral.n100 : Neutral.n900,
    onSurfaceVariant: dark ? Neutral.n400 : Neutral.n500,
    surfaceContainerLowest: dark ? Neutral.n950 : Colors.white,
    surfaceContainerLow: dark ? Neutral.n900 : Neutral.n100,
    surfaceContainer: dark ? Neutral.n850 : Neutral.n100,
    surfaceContainerHigh: dark ? Neutral.n800 : Neutral.n200,
    surfaceContainerHighest: dark ? Neutral.n700 : Neutral.n200,
    outline: dark ? Neutral.n700 : Neutral.n300,
    outlineVariant: dark ? Neutral.n800 : Neutral.n200,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: scheme.outline),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape, minimumSize: const Size(64, 44)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(64, 44),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape)),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: shape,
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: scheme.primary)),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
      backgroundColor: dark ? Neutral.n800 : Neutral.n900,
      contentTextStyle: TextStyle(color: Neutral.n100),
    ),
    dialogTheme: DialogThemeData(
      shape: shape,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: shape,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(shape: shape, minVerticalPadding: 10),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      backgroundColor: scheme.surfaceContainerLow,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.primary, size: 17),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
