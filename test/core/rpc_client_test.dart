
import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late RpcClient rpc;
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
  });

  test('requests have the §6.1 shape', () async {
    final f = rpc.call('sessions.list', {'workspace_id': 'w1'});
    await Future<void>.delayed(Duration.zero);
    expect(sent.single, {
      't': 'req',
      'id': 'r1',
      'method': 'sessions.list',
      'params': {'workspace_id': 'w1'},
    });
    rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': {'sessions': []}});
    expect(await f, {'sessions': []});
  });

  test('responses match by id, in any order', () async {
    final a = rpc.call('a');
    final b = rpc.call('b');
    await Future<void>.delayed(Duration.zero);
    rpc.handleMessage({'t': 'res', 'id': 'r2', 'ok': true, 'result': {'x': 'b'}});
    rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': {'x': 'a'}});
    expect((await a)['x'], 'a');
    expect((await b)['x'], 'b');
    expect(rpc.pendingCount, 0);
  });

  test('error responses become RpcError with code and message', () async {
    final f = rpc.call('chat.send');
    await Future<void>.delayed(Duration.zero);
    rpc.handleMessage({
      't': 'res', 'id': 'r1', 'ok': false,
      'error': {'code': 'yolo_blocked', 'message': 'full access'},
    });
    await expectLater(
        f,
        throwsA(isA<RpcError>()
            .having((e) => e.code, 'code', 'yolo_blocked')
            .having((e) => e.readable, 'readable', contains('Settings → Remote control'))));
  });

  test('times out and ignores the late response', () async {
    final f = rpc.call('hello');
    await expectLater(f, throwsA(isA<RpcError>().having((e) => e.code, 'code', 'timeout')));
    rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': {}});
    expect(rpc.pendingCount, 0);
  });

  test('unknown ids, junk and null result are tolerated', () async {
    rpc.handleMessage({'t': 'res', 'id': 'zzz', 'ok': true});
    rpc.handleMessage('junk');
    rpc.handleMessage(null);
    final f = rpc.call('chat.cancel');
    await Future<void>.delayed(Duration.zero);
    rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': null, 'extra': 1});
    expect(await f, isEmpty);
  });

  test('undeliverable fails the request behind that envelope', () async {
    final f = rpc.call('hello');
    await Future<void>.delayed(Duration.zero);
    rpc.handleUndeliverable('env-r1', 'offline');
    await expectLater(
        f, throwsA(isA<RpcError>().having((e) => e.code, 'code', 'desktop_offline')));
  });

  test('transport failure fails the call', () async {
    final bad = RpcClient(transport: (_) async => throw const RpcError('offline'));
    await expectLater(bad.call('x'), throwsA(isA<RpcError>().having((e) => e.code, 'code', 'offline')));
  });

  test('events are streamed with their name and data', () async {
    final got = <RpcEvent>[];
    final sub = rpc.events.listen(got.add);
    rpc.handleMessage({'t': 'event', 'name': 'status', 'data': {'session_id': 's', 'status': 'idle'}});
    await Future<void>.delayed(Duration.zero);
    expect(got.single.name, 'status');
    expect(got.single.sessionId, 's');
    await sub.cancel();
  });
}
