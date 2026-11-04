import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/agents/agent_cli.dart';

AgentCliInfo cli({bool resume = true, bool bypass = true}) => AgentCliInfo.fromJson({
      'id': 'claude', 'name': 'Claude Code', 'command': 'claude', 'installed': true,
      'has_bypass': bypass, 'has_resume': resume,
    });

void main() {
  test('Terminal.bypass comes from the desktop, missing means false', () {
    final base = {'id': 't', 'title': 'Claude Code', 'kind': 'agent', 'origin': 'desktop', 'cols': 80, 'rows': 24};
    expect(RemoteTerminal.fromJson({...base, 'bypass': true}).bypass, isTrue);
    expect(RemoteTerminal.fromJson(base).bypass, isFalse);
    expect(RemoteTerminal.fromJson({...base, 'bypass': true}).withSize(100, 30).bypass, isTrue);
  });

  group('parsing', () {
    test('AgentCliInfo, missing flags read as false', () {
      final c = cli();
      expect(c.hasResume, isTrue);
      expect(c.hasBypass, isTrue);
      final bare = AgentCliInfo.fromJson({'id': 'x', 'name': 'X', 'command': 'x'});
      expect(bare.installed, isFalse);
      expect(bare.hasBypass, isFalse);
      expect(bare.hasResume, isFalse);
    });

    test('AgentUsageReport with windows and optional fields', () {
      final r = AgentUsageReport.fromJson({
        'id': 'claude', 'name': 'Claude Code', 'status': 'ok', 'plan': 'Max', 'account': 'a@b.c',
        'windows': [
          {'label': '5 h', 'used_percent': 42.5, 'resets_at': 1730000000000, 'detail': 'Opus'},
          {'label': '7 d'},
        ],
        'note': 'from cache', 'updated_at': 5,
      });
      expect(r.status, AgentUsageStatus.ok);
      expect(r.plan, 'Max');
      expect(r.windows.first.usedPercent, 42.5);
      expect(r.windows.first.resetsAt, 1730000000000);
      expect(r.windows.last.usedPercent, isNull);
      expect(r.windows.last.resetsAt, isNull);
      expect(r.windows.last.detail, isNull);
      expect(r.note, 'from cache');
    });

    test('missing optional fields and unknown status → error', () {
      final r = AgentUsageReport.fromJson({'id': 'x', 'name': 'X', 'status': 'rate_limited'});
      expect(r.status, AgentUsageStatus.error);
      expect(r.plan, isNull);
      expect(r.account, isNull);
      expect(r.windows, isEmpty);
      expect(r.note, isNull);
      expect(r.updatedAt, isNull);
      expect(AgentUsageReport.fromJson({}).status, AgentUsageStatus.error);
      expect(AgentUsageStatus.parse('not_signed_in').label, 'not signed in');
      expect(AgentUsageStatus.parse('not_installed').label, 'not installed');
    });

    test('resets in', () {
      expect(resetsIn(null), isNull);
      expect(resetsIn(1000, nowMs: 2000), isNull);
      expect(resetsIn(2 * 3600000 + 5 * 60000, nowMs: 0), 'resets in 2h 5m');
      expect(resetsIn(26 * 3600000, nowMs: 0), 'resets in 1d 2h');
      expect(resetsIn(90000, nowMs: 0), 'resets in 1m');
    });
  });

  group('launch options', () {
    test('toggles are offered only when supported', () {
      expect(launchOptionsFor(cli()), (resume: true, bypass: true));
      expect(launchOptionsFor(cli(resume: false, bypass: false)), (resume: false, bypass: false));
    });

    test('unsupported toggles are never sent', () {
      final p = agentOpenParams(
          cli: cli(resume: false, bypass: false), workspaceId: 'w', cols: 80, rows: 24,
          resume: true, bypass: true);
      expect(p, {'workspace_id': 'w', 'cli_id': 'claude', 'cols': 80, 'rows': 24});
      final q = agentOpenParams(cli: cli(), workspaceId: 'w', cols: 80, rows: 24, resume: true);
      expect(q['resume'], isTrue);
      expect(q.containsKey('bypass'), isFalse);
    });

    group('agent_clis.open', () {
      late List<Json> sent;
      late RpcClient rpc;
      setUp(() {
        sent = [];
        var n = 0;
        rpc = RpcClient(
          transport: (m) async {
            sent.add(m);
            return 'env';
          },
          timeout: const Duration(milliseconds: 200),
          newId: () => 'r${++n}',
        );
      });

      Future<RemoteTerminal?> open({required bool bypass, required bool answer, required List<int> asked}) =>
          openAgentCli(
            rpc: rpc, cli: cli(), workspaceId: 'w', cols: 90, rows: 30, resume: false, bypass: bypass,
            confirmBypass: () async {
              asked.add(1);
              return answer;
            },
          );

      test('bypass asks first; cancelling sends nothing', () async {
        final asked = <int>[];
        expect(await open(bypass: true, answer: false, asked: asked), isNull);
        expect(asked.length, 1);
        expect(sent, isEmpty);
      });

      test('bypass is sent after confirmation; result is the terminal', () async {
        final asked = <int>[];
        final f = open(bypass: true, answer: true, asked: asked);
        await Future<void>.delayed(Duration.zero);
        expect(sent.single['method'], 'agent_clis.open');
        expect(sent.single['params'], {
          'workspace_id': 'w', 'cli_id': 'claude', 'bypass': true, 'cols': 90, 'rows': 30,
        });
        rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': true, 'result': {
          'terminal': {'id': 't9', 'title': 'Claude Code', 'kind': 'agent', 'origin': 'remote',
                       'workspace_id': 'w', 'cols': 90, 'rows': 30},
        }});
        final t = (await f)!;
        expect(t.isAgent, isTrue);
        expect(t.isRemote, isTrue);
      });

      test('no bypass: no confirmation', () async {
        final asked = <int>[];
        final f = open(bypass: false, answer: false, asked: asked);
        await Future<void>.delayed(Duration.zero);
        expect(asked, isEmpty);
        expect(sent.single['params'].containsKey('bypass'), isFalse);
        rpc.handleMessage({'t': 'res', 'id': 'r1', 'ok': false, 'error': {'code': 'not_allowed'}});
        await expectLater(f, throwsA(isA<RpcError>()));
      });
    });

    test('confirmation text names the CLI', () {
      expect(bypassConfirmText('Codex'),
          'Bypass permissions lets Codex run commands and edit files without asking. Continue?');
    });
  });
}

