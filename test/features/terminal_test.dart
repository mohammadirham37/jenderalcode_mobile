import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/terminal/extra_keys.dart';
import 'package:jenderalcode_mobile/features/terminal/terminal_state.dart';

const tid = 't1';

Json term({String origin = 'desktop', int cols = 120, int rows = 40}) => {
      'id': tid, 'title': 'claude', 'kind': 'agent', 'origin': origin,
      'workspace_id': 'w1', 'cols': cols, 'rows': rows, 'extra': true,
    };

RpcEvent ev(String name, Json data) => RpcEvent(name, {'terminal_id': tid, ...data});

void main() {
  group('Terminal model', () {
    test('parses and tolerates missing fields', () {
      final t = RemoteTerminal.fromJson(term(origin: 'remote'));
      expect(t.isRemote, isTrue);
      expect(t.isAgent, isTrue);
      expect(t.cols, 120);
      expect(t.workspaceId, 'w1');
      final bare = RemoteTerminal.fromJson({'id': 'x', 'workspace_id': null});
      expect(bare.kind, 'shell');
      expect(bare.origin, 'desktop');
      expect(bare.workspaceId, isNull);
      expect(RemoteTerminal.listFrom([term(), 'junk']).length, 1);
    });
  });

  group('reducer', () {
    test('attach writes the scrollback into a fresh emulator', () {
      const s0 = TermState(attaching: true);
      final u = reduceAttach(s0, {'terminal': term(), 'scrollback': r'$ ls\r\n'});
      expect(u.reset, isTrue);
      expect(u.output, r'$ ls\r\n');
      expect(u.state.attached, isTrue);
      expect(u.state.attaching, isFalse);
      expect(u.state.generation, 1);
      expect(u.state.cols, 120);
      expect(u.state.rows, 40);
      expect(u.state.info!.isRemote, isFalse);
    });

    test('data appends, exit prints [process exited], resized changes the grid', () {
      var s = reduceAttach(const TermState(), {'terminal': term(), 'scrollback': ''}).state;

      var u = reduceEvent(s, ev('terminal.data', {'data': 'hello'}), tid);
      expect(u.output, 'hello');
      expect(u.reset, isFalse);
      s = u.state;

      u = reduceEvent(s, ev('terminal.resized', {'cols': 100, 'rows': 30}), tid);
      expect(u.output, isEmpty);
      s = u.state;
      expect(s.cols, 100);
      expect(s.rows, 30);

      u = reduceEvent(s, ev('terminal.exit', {'code': 0}), tid);
      expect(u.output, contains(processExitedText));
      expect(u.output, '\r\n[process exited]\r\n');
      s = u.state;
      expect(s.exited, isTrue);
      expect(s.exitCode, 0);

      // A second exit is not printed twice.
      expect(reduceEvent(s, ev('terminal.exit', {'code': null}), tid).output, isEmpty);
    });

    test('exit with a null code', () {
      final s = reduceAttach(const TermState(), {'terminal': term(), 'scrollback': ''}).state;
      final u = reduceEvent(s, ev('terminal.exit', {'code': null}), tid);
      expect(u.state.exited, isTrue);
      expect(u.state.exitCode, isNull);
    });

    test('events for other terminals and malformed data are ignored', () {
      final s = reduceAttach(const TermState(), {'terminal': term(), 'scrollback': ''}).state;
      final other = reduceEvent(
          s, const RpcEvent('terminal.data', {'terminal_id': 'zz', 'data': 'x'}), tid);
      expect(other.output, isEmpty);
      expect(identical(other.state, s), isTrue);
      expect(reduceEvent(s, ev('terminal.data', {'data': 5}), tid).output, isEmpty);
      expect(identical(reduceEvent(s, ev('terminal.resized', {'cols': 'x'}), tid).state, s), isTrue);
    });

    test('re-attach after exit starts clean', () {
      var s = reduceAttach(const TermState(), {'terminal': term(), 'scrollback': 'a'}).state;
      s = reduceEvent(s, ev('terminal.exit', {'code': 1}), tid).state;
      final u = reduceAttach(s, {'terminal': term(), 'scrollback': 'a\r\nb'});
      expect(u.state.exited, isFalse);
      expect(u.state.exitCode, isNull);
      expect(u.state.generation, 2);
      expect(u.output, 'a\r\nb');
    });
  });

  group('extra keys', () {
    test('escape sequences', () {
      expect(extraKeySequence(ExtraKey.esc), '\x1b');
      expect(extraKeySequence(ExtraKey.tab), '\t');
      expect(extraKeySequence(ExtraKey.ctrlC), '\x03');
      expect(extraKeySequence(ExtraKey.enter), '\r');
      expect(extraKeySequence(ExtraKey.up), '\x1b[A');
      expect(extraKeySequence(ExtraKey.down), '\x1b[B');
      expect(extraKeySequence(ExtraKey.right), '\x1b[C');
      expect(extraKeySequence(ExtraKey.left), '\x1b[D');
      expect(extraKeySequence(ExtraKey.pipe), '|');
      expect(extraKeySequence(ExtraKey.tilde), '~');
      expect(extraKeySequence(ExtraKey.slash), '/');
      expect(extraKeySequence(ExtraKey.dash), '-');
      expect(extraKeySequence(ExtraKey.ctrl), isNull);
    });

    test('application cursor mode and Ctrl+arrow', () {
      expect(extraKeySequence(ExtraKey.up, appCursor: true), '\x1bOA');
      expect(extraKeySequence(ExtraKey.left, ctrl: true), '\x1b[1;5D');
    });

    test('sticky Ctrl turns letters into control codes', () {
      expect(applyCtrl('c'), '\x03');
      expect(applyCtrl('C'), '\x03');
      expect(applyCtrl('d'), '\x04');
      expect(applyCtrl('['), '\x1b');
      expect(applyCtrl(' '), '\x00');
      expect(applyCtrl('?'), '\x7f');
      expect(applyCtrl('ab'), 'ab');
    });

    test('input is chunked under 64 KiB without splitting surrogates', () {
      expect(chunkInput('abc'), ['abc']);
      final big = 'x' * 40000;
      final parts = chunkInput(big);
      expect(parts.join(), big);
      expect(parts.every((p) => p.length <= 16384), isTrue);
      final emoji = '${'a' * 16383}😀b';
      final ep = chunkInput(emoji);
      expect(ep.join(), emoji);
      expect(ep.first.length, 16383);
    });
  });
}
