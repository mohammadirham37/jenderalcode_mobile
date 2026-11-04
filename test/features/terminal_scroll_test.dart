import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/features/terminal/extra_keys.dart';
import 'package:xterm/xterm.dart';

/// What a one-finger drag over a full-screen program turns into
/// (TerminalSessionController.scrollProgram).
void main() {
  Terminal term(String setup) => Terminal()
    ..resize(60, 20)
    ..write(setup);

  String? wheel(Terminal t, {required bool up}) => wheelSequence(
      up: up, mode: t.mouseMode, report: t.mouseReportMode, col: 31, row: 11);

  test('Codex/OpenCode (alt screen + SGR mouse): standard wheel codes 64/65', () {
    final t = term('\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h');
    expect(t.isUsingAltBuffer, isTrue);
    expect(wheel(t, up: true), '\x1b[<64;31;11M');
    expect(wheel(t, up: false), '\x1b[<65;31;11M');
  });

  test('legacy X10 encoding', () {
    final t = term('\x1b[?1049h\x1b[?1000h');
    expect(wheel(t, up: true), '\x1b[M${String.fromCharCode(96)}${String.fromCharCode(63)}${String.fromCharCode(43)}');
  });

  test('Antigravity (alt screen, no mouse): no wheel, arrow keys instead', () {
    final t = term('\x1b[?1049h');
    expect(t.isUsingAltBuffer, isTrue);
    expect(wheel(t, up: true), isNull);
    expect(extraKeySequence(ExtraKey.up, ctrl: false, appCursor: t.cursorKeysMode), '\x1b[A');
  });

  test('Claude Code (main screen): the view scrolls its own scrollback', () {
    expect(term('\x1b[?2004h').isUsingAltBuffer, isFalse);
  });

  test('PgUp / PgDn keys', () {
    expect(extraKeySequence(ExtraKey.pgUp, ctrl: false, appCursor: false), '\x1b[5~');
    expect(extraKeySequence(ExtraKey.pgDn, ctrl: false, appCursor: false), '\x1b[6~');
  });
}
