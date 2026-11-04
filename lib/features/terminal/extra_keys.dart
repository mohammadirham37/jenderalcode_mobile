import 'package:xterm/xterm.dart';

/// Keys of the bar above the soft keyboard. Agent CLIs (Claude Code, Codex)
/// need Esc, arrows, Ctrl+C and Enter, which phone keyboards lack.
enum ExtraKey {
  esc('Esc'),
  tab('Tab'),
  ctrl('Ctrl'),
  ctrlC('^C'),
  left('←'),
  up('↑'),
  down('↓'),
  right('→'),
  pgUp('PgUp'),
  pgDn('PgDn'),
  pipe('|'),
  tilde('~'),
  slash('/'),
  dash('-'),
  enter('⏎');

  const ExtraKey(this.label);
  final String label;
}

/// Applies Ctrl to typed text the way a terminal does. Only single
/// characters are changed; anything else (paste, IME words) passes through.
String applyCtrl(String text) {
  if (text.length != 1) return text;
  final c = text.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60); // a-z
  if (c >= 0x40 && c <= 0x5f) return String.fromCharCode(c - 0x40); // @ A-Z [ \ ] ^ _
  return switch (text) {
    ' ' || '2' => '\x00',
    '3' => '\x1b',
    '4' || '|' => '\x1c',
    '5' => '\x1d',
    '6' || '~' => '\x1e',
    '7' || '/' || '-' => '\x1f',
    '8' || '?' => '\x7f',
    _ => text,
  };
}

/// The bytes one extra key sends. [ctrl] is the sticky modifier; [appCursor]
/// is DECCKM (application cursor keys, `ESC [ ? 1 h`), which full-screen
/// programs switch on. Returns null for [ExtraKey.ctrl] (it only arms).
String? extraKeySequence(ExtraKey k, {bool ctrl = false, bool appCursor = false}) {
  String arrow(String c) => ctrl ? '\x1b[1;5$c' : (appCursor ? '\x1bO$c' : '\x1b[$c');
  return switch (k) {
    ExtraKey.ctrl => null,
    ExtraKey.esc => '\x1b',
    ExtraKey.tab => '\t',
    ExtraKey.ctrlC => '\x03',
    ExtraKey.enter => '\r',
    ExtraKey.up => arrow('A'),
    ExtraKey.down => arrow('B'),
    ExtraKey.right => arrow('C'),
    ExtraKey.left => arrow('D'),
    ExtraKey.pgUp => '\x1b[5~',
    ExtraKey.pgDn => '\x1b[6~',
    ExtraKey.pipe => ctrl ? applyCtrl('|') : '|',
    ExtraKey.tilde => ctrl ? applyCtrl('~') : '~',
    ExtraKey.slash => ctrl ? applyCtrl('/') : '/',
    ExtraKey.dash => ctrl ? applyCtrl('-') : '-',
  };
}

/// Splits text for `terminal.input` (≤ 64 KiB per request, UTF-8). 16 Ki
/// UTF-16 units encode to at most 48 KiB; surrogate pairs are kept whole.
List<String> chunkInput(String data, {int maxUnits = 16384}) {
  if (data.length <= maxUnits) return [data];
  final out = <String>[];
  var i = 0;
  while (i < data.length) {
    var end = i + maxUnits;
    if (end >= data.length) {
      end = data.length;
    } else {
      final c = data.codeUnitAt(end - 1);
      if (c >= 0xD800 && c <= 0xDBFF) end -= 1; // don't split a surrogate pair
    }
    out.add(data.substring(i, end));
    i = end;
  }
  return out;
}

/// One mouse-wheel step as the program asked to receive it, or null when it
/// does not report scrolling. Written here because xterm.dart 4.0.0 encodes
/// wheel buttons as 68/69 (the Shift-modified codes) instead of 64/65, which
/// Codex and OpenCode read as horizontal or Shift scrolling. [col] and [row]
/// are 1-based.
String? wheelSequence({
  required bool up,
  required MouseMode mode,
  required MouseReportMode report,
  required int col,
  required int row,
}) {
  if (!mode.reportScroll) return null;
  final code = up ? 64 : 65;
  return switch (report) {
    MouseReportMode.sgr => '\x1b[<$code;$col;${row}M',
    MouseReportMode.urxvt => '\x1b[${code + 32};$col;${row}M',
    _ => '\x1b[M${String.fromCharCode(32 + code)}'
        '${String.fromCharCode(32 + col.clamp(1, 223))}${String.fromCharCode(32 + row.clamp(1, 223))}',
  };
}
