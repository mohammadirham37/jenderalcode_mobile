import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/features/chat/todos.dart';

ToolRun run(String id, int at, Object? todos, {String tool = 'todo_write', String status = 'success'}) =>
    ToolRun.fromJson({
      'id': id,
      'session_id': 's',
      'tool_name': tool,
      'status': status,
      'args': {'todos': todos},
      'created_at': at,
    });

void main() {
  test('the newest successful todo_write is the checklist', () {
    final runs = [
      run('a', 1, [{'content': 'Old', 'status': 'pending'}]),
      run('b', 3, [
        {'content': 'Read config', 'status': 'completed'},
        {'content': 'Add route', 'status': 'in_progress'},
        {'content': 'Run tests', 'status': 'pending'},
        {'content': '  ', 'status': 'pending'},
      ]),
      run('c', 5, [{'content': 'Failed write', 'status': 'pending'}], status: 'error'),
      run('d', 6, [{'content': 'Not a todo'}], tool: 'fs_read'),
    ];
    final t = latestTodos(runs)!;
    expect(t.map((e) => e.content), ['Read config', 'Add route', 'Run tests']);
    expect(t[0].done, isTrue);
    expect(t[1].active, isTrue);
    expect(t[2].status, 'pending');
  });

  test('no checklist', () {
    expect(latestTodos(const []), isNull);
    expect(latestTodos([run('a', 1, 'garbage')]), isNull);
    expect(latestTodos([run('a', 1, [])]), isNull);
  });
}
