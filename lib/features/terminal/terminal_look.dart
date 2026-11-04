import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme/app_theme.dart';

/// Same palettes as the desktop's xterm registry (DARK / LIGHT).
const darkTerminalTheme = TerminalTheme(
  cursor: Color(0xFF2FC3A5),
  selection: Color(0x5513A68B),
  foreground: Color(0xFFD6DDDA),
  background: Color(0xFF0C0F0E),
  black: Color(0xFF151A18),
  red: Color(0xFFCD3131),
  green: Color(0xFF2FC3A5),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF67746F),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF62DBBF),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF7FD3DC),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF62DBBF),
  searchHitBackgroundCurrent: Color(0xFF2FC3A5),
  searchHitForeground: Color(0xFF0C0F0E),
);

/// "white" is dark grey: CLIs print plain text in white, which would vanish
/// on a light background.
const lightTerminalTheme = TerminalTheme(
  cursor: Color(0xFF0B8672),
  selection: Color(0x4013A68B),
  foreground: Color(0xFF1C2220),
  background: Color(0xFFF5F7F6),
  black: Color(0xFF1C2220),
  red: Color(0xFFC2412D),
  green: Color(0xFF0B8672),
  yellow: Color(0xFF9A6700),
  blue: Color(0xFF2A62B8),
  magenta: Color(0xFF8E44AD),
  cyan: Color(0xFF0E7490),
  white: Color(0xFF67746F),
  brightBlack: Color(0xFF4E5954),
  brightRed: Color(0xFFD4513D),
  brightGreen: Color(0xFF0D6B5C),
  brightYellow: Color(0xFF7C5800),
  brightBlue: Color(0xFF1D4F99),
  brightMagenta: Color(0xFF7A3B96),
  brightCyan: Color(0xFF0B5F75),
  brightWhite: Color(0xFF252D2A),
  searchHitBackground: Color(0xFF62DBBF),
  searchHitBackgroundCurrent: Color(0xFF2FC3A5),
  searchHitForeground: Color(0xFF0C0F0E),
);

TerminalTheme terminalThemeFor(Brightness b) =>
    b == Brightness.dark ? darkTerminalTheme : lightTerminalTheme;

const double defaultTerminalFontSize = 12;
const double minTerminalFontSize = 5;
const double maxTerminalFontSize = 24;

/// Padding inside the terminal view, on each side.
const double terminalPadding = 4;

TerminalStyle terminalStyle(double fontSize) =>
    TerminalStyle(fontSize: fontSize, fontFamily: monoFamily);

/// Cell size for [style] without text scaling: the same measurement xterm's
/// renderer makes, so cols/rows computed here match the view.
Size measureCell(TerminalStyle style) {
  const sample = 'mmmmmmmmmm';
  final ts = style.toTextStyle();
  final b = ui.ParagraphBuilder(ts.getParagraphStyle())
    ..pushStyle(ts.getTextStyle(textScaler: TextScaler.noScaling))
    ..addText(sample);
  final p = b.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  return Size(p.maxIntrinsicWidth / sample.length, p.height);
}

/// How many cells fit in [area] (before padding).
({int cols, int rows}) gridFor(Size area, Size cell) {
  final w = area.width - terminalPadding * 2;
  final h = area.height - terminalPadding * 2;
  return (
    cols: (w / cell.width).floor().clamp(20, 500),
    rows: (h / cell.height).floor().clamp(5, 300),
  );
}

/// Grid estimate for a full-screen terminal on this phone, used when
/// opening one; the terminal screen sends the exact size once laid out.
({int cols, int rows}) phoneGrid(BuildContext context) {
  final mq = MediaQuery.of(context);
  final cell = measureCell(terminalStyle(defaultTerminalFontSize));
  return gridFor(
    Size(mq.size.width, mq.size.height - mq.padding.vertical - kToolbarHeight - 48),
    cell,
  );
}
