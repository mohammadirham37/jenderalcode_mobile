import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/chat/policy.dart';

Json session(String? mode) => {
      'id': 's1', 'workspace_id': 'w1', 'title': 'T', 'policy_mode': mode,
      'created_at': 1, 'updated_at': 2, 'message_count': 0,
    };

void main() {
  const allowed = Capabilities(fullAccess: true, terminal: true, edit: true);

  group('session.set_policy', () {
    late List<Json> sent;
    late RpcClient rpc;
    setUp(() {
      sent = [];
      var n = 0;
      rpc = RpcClient(
        transport: (m) async {
          sent.add(m);
          return 'env-${m['id']}';
        },
        timeout: const Duration(milliseconds: 200),
        newId: () => 'r${++n}',
      );
    });

    test('sends session_id and mode, returns the updated session', () async {
      final f = setSessionPolicy(rpc, 's1', 'balanced');
      await Future<void>.delayed(Duration.zero);
      expect(sent.single, {
        't': 'req', 'id': 'r1', 'method': 'session.set_policy',
        'params': {'session_id': 's1', 'mode': 'balanced'},
      });
      rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': {'session': session('balanced')}});
      final s = await f;
      expect(s.policyMode, 'balanced');
      expect(s.isYolo, isFalse);
    });

    test('yolo_blocked and not_allowed surface as RpcError', () async {
      final f = setSessionPolicy(rpc, 's1', 'yolo');
      await Future<void>.delayed(Duration.zero);
      rpc.handleMessage({
        't': 'res', 'id': 'r1', 'ok': false,
        'error': {'code': 'not_allowed', 'message': 'off'},
      });
      await expectLater(f, throwsA(isA<RpcError>().having((e) => e.code, 'code', 'not_allowed')));
    });
  });

  group('Full access gating', () {
    late List<String> sentModes;
    late int confirms;
    Future<PolicyChange> run(String mode, {String? current, Capabilities caps = allowed, bool answer = true}) {
      return changePolicy(
        mode: mode,
        current: current,
        caps: caps,
        confirmFullAccess: () async {
          confirms++;
          return answer;
        },
        send: (m) async {
          sentModes.add(m);
          return Session.fromJson(session(m));
        },
      );
    }

    setUp(() {
      sentModes = [];
      confirms = 0;
    });

    test('safe and balanced are sent without confirmation', () async {
      expect(await run('safe', current: 'balanced'), isA<PolicyChanged>());
      expect(await run('balanced', current: null), isA<PolicyChanged>());
      expect(sentModes, ['safe', 'balanced']);
      expect(confirms, 0);
    });

    test('yolo asks first; cancelling sends nothing', () async {
      final r = await run('yolo', current: 'balanced', answer: false);
      expect(r, isA<PolicyNotSent>().having((r) => r.reason, 'reason', 'cancelled'));
      expect(confirms, 1);
      expect(sentModes, isEmpty);
    });

    test('yolo is sent after confirmation', () async {
      final r = await run('yolo', current: 'safe');
      expect(confirms, 1);
      expect(sentModes, ['yolo']);
      expect((r as PolicyChanged).session.isYolo, isTrue);
    });

    test('yolo is not offered or sent when full_access is false', () async {
      expect(policyModeAllowed('yolo', Capabilities.none), isFalse);
      expect(policyModeAllowed('safe', Capabilities.none), isTrue);
      final r = await run('yolo', caps: Capabilities.none);
      expect(r, isA<PolicyNotSent>().having((r) => r.reason, 'reason', 'not_allowed'));
      expect(confirms, 0);
      expect(sentModes, isEmpty);
    });

    test('same mode is a no-op; send errors become PolicyFailed', () async {
      expect(await run('safe', current: 'safe'), isA<PolicyNotSent>());
      final r = await changePolicy(
        mode: 'balanced',
        current: 'safe',
        caps: allowed,
        confirmFullAccess: () async => true,
        send: (_) async => throw const RpcError('yolo_blocked'),
      );
      expect((r as PolicyFailed).error.code, 'yolo_blocked');
    });

    test('labels', () {
      expect(policyLabel(null), 'Default');
      expect(policyLabel('yolo'), 'Full access');
      expect(policyLabel('safe'), 'Safe');
      expect(policyLabel('balanced'), 'Balanced');
      expect(fullAccessConfirmText, contains('Anyone holding this phone can then control your computer'));
    });
  });
}
