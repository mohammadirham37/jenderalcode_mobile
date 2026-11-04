import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../sessions/sessions_providers.dart';

/// `agents.list` for one desktop.
final agentsProvider =
    FutureProvider.autoDispose.family<List<Agent>, String>((ref, desktopId) async {
  final r = await rpcFor(ref, desktopId).call('agents.list');
  return Agent.listFrom(r['agents']);
}, retry: (_, _) => null);

/// `models.list` for one desktop (enabled providers only).
final modelsProvider =
    FutureProvider.autoDispose.family<ModelCatalog, String>((ref, desktopId) async {
  final r = await rpcFor(ref, desktopId).call('models.list');
  return ModelCatalog.fromJson(r);
}, retry: (_, _) => null);

/// `skills.list` for the `/` menu.
final skillsProvider =
    FutureProvider.autoDispose.family<List<Skill>, WorkspaceKey>((ref, k) async {
  final r = await rpcFor(ref, k.desktopId).call('skills.list', {'workspace_id': k.workspaceId});
  return Skill.listFrom(r['skills']);
}, retry: (_, _) => null);

/// `checkpoints.list` for one session.
final checkpointsProvider = FutureProvider.autoDispose
    .family<List<Checkpoint>, ({String desktopId, String sessionId})>((ref, k) async {
  final r = await rpcFor(ref, k.desktopId).call('checkpoints.list', {'session_id': k.sessionId});
  return Checkpoint.listFrom(r['checkpoints']);
}, retry: (_, _) => null);
