import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

RpcClient rpcFor(Ref ref, String desktopId) {
  final hub = ref.watch(hubProvider);
  if (hub == null || !hub.isKnown(desktopId)) {
    throw const RpcError('not_paired', 'This desktop is not paired.');
  }
  return hub.rpc(desktopId);
}

class DesktopOverview {
  const DesktopOverview(this.hello, this.workspaces);
  final HelloResult hello;
  final List<Workspace> workspaces;
}

final desktopOverviewProvider =
    FutureProvider.autoDispose.family<DesktopOverview, String>((ref, desktopId) async {
  final rpc = rpcFor(ref, desktopId);
  final hello = HelloResult.fromJson(
      await rpc.call('hello', {'app_version': AppConfig.appVersion}));
  final ws = Workspace.listFrom((await rpc.call('workspaces.list'))['workspaces'])
    ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  return DesktopOverview(hello, ws);
}, retry: (_, _) => null);

typedef WorkspaceKey = ({String desktopId, String workspaceId});

final sessionsProvider =
    FutureProvider.autoDispose.family<List<Session>, WorkspaceKey>((ref, k) async {
  final rpc = rpcFor(ref, k.desktopId);
  final r = await rpc.call('sessions.list', {'workspace_id': k.workspaceId});
  return Session.listFrom(r['sessions'])
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}, retry: (_, _) => null);
