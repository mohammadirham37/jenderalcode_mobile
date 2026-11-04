import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/project/project_api.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late RpcClient rpc;
  late ProjectApi api;
  var n = 0;

  setUp(() {
    sent = [];
    n = 0;
    rpc = RpcClient(
      transport: (m) async {
        sent.add(m);
        return 'env-${m['id']}';
      },
      timeout: const Duration(milliseconds: 200),
      newId: () => 'r${++n}',
    );
    api = ProjectApi(rpc, 'w1');
  });

  Future<T> answer<T>(Future<T> f, Object result) async {
    await Future<void>.delayed(Duration.zero);
    rpc.handleMessage({'t': 'res', 'id': 'r$n', 'ok': true, 'result': result});
    return f;
  }

  test('fs.list / fs.read / fs.rename params (§6.7)', () async {
    final entries = await answer(api.list('src', showHidden: true), {
      'entries': [
        {'path': 'src/a.ts', 'name': 'a.ts', 'is_dir': false, 'size': 12},
        {'path': 'src/lib', 'name': 'lib', 'is_dir': true},
      ],
    });
    expect(sent.last['method'], 'fs.list');
    expect(sent.last['params'], {'workspace_id': 'w1', 'path': 'src', 'show_hidden': true});
    expect(entries.first.size, 12);
    expect(entries.last.isDir, isTrue);
    expect(entries.last.size, isNull);

    final f = await answer(api.read('src/a.ts'), {'path': 'src/a.ts', 'content': 'x', 'size': 1});
    expect(f.content, 'x');

    final r = api.rename('a', 'b');
    await answer(r, {});
    expect(sent.last['params'], {'workspace_id': 'w1', 'from': 'a', 'to': 'b'});
  });

  test('git.diff omits a missing path and parses the diff (§6.8)', () async {
    final files = await answer(api.diff(staged: true), {
      'diff': 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n',
    });
    expect(sent.last['method'], 'git.diff');
    expect(sent.last['params'], {'workspace_id': 'w1', 'staged': true});
    expect(files.single.path, 'x');

    await answer(api.diffHead(path: 'x'), {'diff': ''});
    expect(sent.last['params'], {'workspace_id': 'w1', 'path': 'x'});

    final hash = await answer(api.commit('msg'), {'hash': 'abc'});
    expect(hash, 'abc');
    expect(sent.last['params'], {'workspace_id': 'w1', 'message': 'msg'});

    await answer(api.stage(['a', 'b']), {});
    expect(sent.last['params'], {'workspace_id': 'w1', 'paths': ['a', 'b']});
  });
}
