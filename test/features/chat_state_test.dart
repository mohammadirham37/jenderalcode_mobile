import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/chat/chat_state.dart';

const sid = 's1';

RpcEvent ev(String name, Map<String, dynamic> data) =>
    RpcEvent(name, {'session_id': sid, ...data});

Map<String, dynamic> msg(String id, String role, String content, int at, {String? reasoning}) => {
      'id': id, 'session_id': sid, 'role': role, 'content': content,
      'tool_calls': [], 'images': [], 'created_at': at,
      'reasoning': reasoning, 'unknown_field': true,
    };

void main() {
  final history = SessionHistory.fromJson({
    'session': {
      'id': sid, 'workspace_id': 'w', 'title': 'T', 'policy_mode': 'balanced',
      'created_at': 1, 'updated_at': 2, 'message_count': 1,
    },
    'messages': [msg('u1', 'user', 'hi', 100)],
    'tool_runs': [],
    'approvals': [],
    'busy': false,
  });

  test('deltas append to one streaming message, then message replaces it', () {
    var s = const ChatState().withHistory(history);
    s = s.applyEvent(ev('delta', {'message_id': 'a1', 'delta': 'Hel', 'reasoning': false}), sid);
    s = s.applyEvent(ev('delta', {'message_id': 'a1', 'delta': 'lo', 'reasoning': false}), sid);
    s = s.applyEvent(ev('delta', {'message_id': 'a1', 'delta': 'think', 'reasoning': true}), sid);
    expect(s.messages.length, 2);
    final live = s.messages.last;
    expect(live.id, 'a1');
    expect(live.content, 'Hello');
    expect(live.reasoning, 'think');
    expect(live.streaming, isTrue);
    expect(live.createdAt, greaterThan(100));

    s = s.applyEvent(ev('message', {'message': msg('a1', 'assistant', 'Hello there', 150, reasoning: 'think')}), sid);
    expect(s.messages.length, 2);
    expect(s.messages.last.content, 'Hello there');
    expect(s.messages.last.streaming, isFalse);
    expect(s.messages.last.createdAt, 150);
  });

  test('a message event with a new id is appended', () {
    var s = const ChatState().withHistory(history);
    s = s.applyEvent(ev('message', {'message': msg('u2', 'user', 'again', 200)}), sid);
    expect(s.messages.map((m) => m.id), ['u1', 'u2']);
  });

  test('events for other sessions are ignored', () {
    final s = const ChatState().withHistory(history);
    final s2 = s.applyEvent(
        const RpcEvent('delta', {'session_id': 'other', 'message_id': 'x', 'delta': 'y', 'reasoning': false}), sid);
    expect(identical(s, s2), isTrue);
  });

  test('status drives busy; tool runs and approvals upsert', () {
    var s = const ChatState().withHistory(history);
    s = s.applyEvent(ev('status', {'status': 'running_tool', 'detail': 'fs_write'}), sid);
    expect(s.busy, isTrue);
    expect(s.detail, 'fs_write');
    final run = {
      'id': 'r1', 'session_id': sid, 'tool_name': 'fs_write', 'status': 'awaiting_approval',
      'args': {'path': 'a.txt'}, 'approval_id': 'ap1', 'created_at': 300,
    };
    s = s.applyEvent(ev('tool_run', {'run': run}), sid);
    s = s.applyEvent(ev('approval', {'approval': {
      'id': 'ap1', 'session_id': sid, 'tool_run_id': 'r1', 'kind': 'write_file',
      'description': 'Write a.txt', 'preview': '+hello', 'status': 'pending', 'created_at': 301,
    }}), sid);
    expect(s.pendingApprovals.single.id, 'ap1');
    final tl = buildTimeline(s);
    expect(tl.last, isA<ToolRunItem>());
    expect((tl.last as ToolRunItem).approval?.id, 'ap1');

    s = s.applyEvent(ev('tool_run', {'run': {...run, 'status': 'success', 'result_summary': 'ok'}}), sid);
    expect(s.toolRuns.length, 1);
    expect(s.toolRuns['r1']!.status, 'success');
    s = s.applyEvent(ev('status', {'status': 'idle', 'detail': null}), sid);
    expect(s.busy, isFalse);
  });

  test('error and usage events', () {
    var s = const ChatState().withHistory(history);
    s = s.applyEvent(ev('error', {'error': 'model failed'}), sid);
    expect(s.lastError, 'model failed');
    s = s.applyEvent(ev('usage', {'input_tokens': 10, 'output_tokens': 5, 'cost_estimate': null}), sid);
    expect(s.inputTokens, 10);
    expect(s.costEstimate, isNull);
  });

  test('timeline hides tool messages and empty tool-call assistant messages', () {
    var s = const ChatState().withHistory(history);
    s = s.applyEvent(ev('message', {'message': msg('a0', 'assistant', '', 110)}), sid);
    s = s.applyEvent(ev('message', {'message': msg('t0', 'tool', 'result', 111)}), sid);
    final tl = buildTimeline(s);
    expect(tl.length, 1);
    expect((tl.single as MessageItem).message.id, 'u1');
  });
}
