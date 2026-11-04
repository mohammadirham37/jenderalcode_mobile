import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/project/gating.dart';
import 'package:jenderalcode_mobile/features/project/git_model.dart';

void main() {
  test('git.status groups staged and unstaged files', () {
    final st = GitStatus.fromJson({
      'branch': 'main',
      'files': [
        {'path': 'a.ts', 'index': 'modified', 'worktree': 'unmodified'},
        {'path': 'b.ts', 'index': 'unmodified', 'worktree': 'modified'},
        {'path': 'c.ts', 'index': 'added', 'worktree': 'modified'},
        {'path': 'new.txt', 'index': 'untracked', 'worktree': 'untracked'},
        {'path': 'gone.txt', 'index': 'deleted', 'worktree': 'unmodified'},
        {'path': 'odd', 'index': 'something_new', 'worktree': 'unmodified', 'extra': 1},
      ],
    });
    expect(st.branch, 'main');
    final g = st.groups;
    expect(g.staged.map((f) => f.path), ['a.ts', 'c.ts', 'gone.txt', 'odd']);
    expect(g.unstaged.map((f) => f.path), ['b.ts', 'c.ts', 'new.txt']);
    expect(st.files.last.index, StatusKind.other);
    expect(displayKind(st.files[2], staged: true), StatusKind.added);
    expect(displayKind(st.files[2], staged: false), StatusKind.modified);
    expect(StatusKind.untracked.letter, '?');
  });

  test('detached HEAD and clean tree', () {
    final st = GitStatus.fromJson({'branch': null, 'files': []});
    expect(st.branch, isNull);
    expect(st.groups.isClean, isTrue);
  });

  test('Commit and Branch parsing', () {
    final c = Commit.listFrom([
      {'hash': 'abcdef1234567', 'short_hash': 'abcdef1', 'subject': 'Fix', 'author': 'Ana', 'timestamp': 1730000000},
      {'hash': 'ffff', 'short_hash': 'ffff', 'subject': 'Ms', 'author': 'Bo', 'timestamp': 1730000000000},
    ]);
    expect(c.first.shortHash, 'abcdef1');
    expect(c.first.subject, 'Fix');
    expect(c.first.timestampMs, 1730000000000);
    expect(c.last.timestampMs, 1730000000000);
    final b = Branch.listFrom([
      {'name': 'main', 'current': true},
      {'name': 'dev'},
    ]);
    expect(b.map((x) => x.current), [true, false]);
  });

  group('edit capability gating', () {
    const on = Capabilities(fullAccess: true, terminal: true, edit: true);
    const off = Capabilities(fullAccess: true, terminal: true, edit: false);

    test('performWrite never sends when edit is off', () async {
      var calls = 0;
      final err = await performWrite(off, () async => calls++);
      expect(calls, 0);
      expect(err?.code, 'not_allowed');
      expect(await performWrite(Capabilities.none, () async => calls++), isNotNull);
      expect(calls, 0);
    });

    test('performWrite sends when edit is on and reports desktop errors', () async {
      var calls = 0;
      expect(await performWrite(on, () async => calls++), isNull);
      expect(calls, 1);
      final err = await performWrite(on, () async => throw const RpcError('not_allowed', 'off'));
      expect(err?.code, 'not_allowed');
    });

    test('whenEditable disables actions', () {
      void f() {}
      expect(whenEditable(on, f), isNotNull);
      expect(whenEditable(off, f), isNull);
      expect(canEdit(off), isFalse);
    });
  });

  test('relative path validation and helpers', () {
    expect(validateRelativePath('src/a.txt'), isNull);
    expect(validateRelativePath(''), isNotNull);
    expect(validateRelativePath('/etc/passwd'), isNotNull);
    expect(validateRelativePath('../x'), isNotNull);
    expect(validateRelativePath('a//b'), isNotNull);
    expect(joinPath('', 'a'), 'a');
    expect(joinPath('src', 'a'), 'src/a');
    expect(parentOf('src/lib/a.dart'), 'src/lib');
    expect(parentOf('a.dart'), '');
    expect(baseName('src/a.dart'), 'a.dart');
  });
}
