import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../sessions/sessions_providers.dart';

/// `agent_clis.list` for one desktop.
final agentClisProvider =
    FutureProvider.autoDispose.family<List<AgentCliInfo>, String>((ref, desktopId) async {
  final r = await rpcFor(ref, desktopId).call('agent_clis.list');
  return AgentCliInfo.listFrom(r['clis']);
}, retry: (_, _) => null);

/// `agent_clis.usage` (can take several seconds).
final agentUsageProvider =
    FutureProvider.autoDispose.family<List<AgentUsageReport>, String>((ref, desktopId) async {
  final r = await rpcFor(ref, desktopId).call('agent_clis.usage');
  return AgentUsageReport.listFrom(r['reports']);
}, retry: (_, _) => null);

/// Terminal ids this phone opened with bypass, for the red ShieldOff mark.
/// Fallback until the desktop's `Terminal.bypass` arrives (older desktops
/// do not send it).
class BypassTerminals extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void add(String id) => state = {...state, id};
}

final bypassTerminalsProvider =
    NotifierProvider<BypassTerminals, Set<String>>(BypassTerminals.new);

/// Which launch toggles a preset offers.
({bool resume, bool bypass}) launchOptionsFor(AgentCliInfo cli) =>
    (resume: cli.hasResume, bypass: cli.hasBypass);

String bypassConfirmText(String name) =>
    'Bypass permissions lets $name run commands and edit files without asking. Continue?';

/// Params for `agent_clis.open`; unsupported toggles are never sent.
Json agentOpenParams({
  required AgentCliInfo cli,
  required String workspaceId,
  required int cols,
  required int rows,
  bool resume = false,
  bool bypass = false,
}) {
  final o = launchOptionsFor(cli);
  return {
    'workspace_id': workspaceId,
    'cli_id': cli.id,
    if (o.resume && resume) 'resume': true,
    if (o.bypass && bypass) 'bypass': true,
    'cols': cols,
    'rows': rows,
  };
}

/// Opens [cli]; bypass is only sent after [confirmBypass] says yes. Returns
/// null when the user cancelled the bypass confirmation.
Future<RemoteTerminal?> openAgentCli({
  required RpcClient rpc,
  required AgentCliInfo cli,
  required String workspaceId,
  required int cols,
  required int rows,
  required bool resume,
  required bool bypass,
  required Future<bool> Function() confirmBypass,
}) async {
  final wantBypass = bypass && cli.hasBypass;
  if (wantBypass && !await confirmBypass()) return null;
  final r = await rpc.call(
    'agent_clis.open',
    agentOpenParams(
        cli: cli, workspaceId: workspaceId, cols: cols, rows: rows, resume: resume, bypass: wantBypass),
  );
  final raw = r['terminal'];
  if (raw is! Map) throw const RpcError('internal', 'The desktop sent no terminal.');
  return RemoteTerminal.fromJson(raw.cast<String, dynamic>());
}

/// "resets in 2h 5m" from epoch ms; null when unknown or past.
String? resetsIn(int? resetsAtMs, {int? nowMs}) {
  if (resetsAtMs == null) return null;
  final d = Duration(milliseconds: resetsAtMs - (nowMs ?? DateTime.now().millisecondsSinceEpoch));
  if (d.isNegative) return null;
  if (d.inDays >= 1) return 'resets in ${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return 'resets in ${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes >= 1) return 'resets in ${d.inMinutes}m';
  return 'resets in <1m';
}
