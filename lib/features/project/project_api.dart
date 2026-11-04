import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../sessions/sessions_providers.dart';
import 'diff.dart';
import 'git_model.dart';

typedef ProjectKey = ({String desktopId, String workspaceId});

/// Typed wrapper over the §6.7 (files) and §6.8 (git) methods for one project.
class ProjectApi {
  ProjectApi(this.rpc, this.workspaceId);
  final RpcClient rpc;
  final String workspaceId;

  Json _p([Json extra = const {}]) => {'workspace_id': workspaceId, ...extra};

  // §6.7 Files and Editor.
  Future<List<FileEntry>> list(String path, {bool showHidden = false}) async {
    final r = await rpc.call('fs.list', _p({'path': path, 'show_hidden': showHidden}));
    return FileEntry.listFrom(r['entries']);
  }

  Future<FileContent> read(String path) async =>
      FileContent.fromJson(await rpc.call('fs.read', _p({'path': path})), path);

  Future<void> write(String path, String content) =>
      rpc.call('fs.write', _p({'path': path, 'content': content}));

  Future<void> create(String path, {required bool isDir}) =>
      rpc.call('fs.create', _p({'path': path, 'is_dir': isDir}));

  Future<void> delete(String path) => rpc.call('fs.delete', _p({'path': path}));

  Future<void> rename(String from, String to) =>
      rpc.call('fs.rename', _p({'from': from, 'to': to}));

  // §6.8 Changes and Git.
  Future<GitStatus> status() async => GitStatus.fromJson(await rpc.call('git.status', _p()));

  Future<List<DiffFile>> diff({String? path, bool staged = false}) async {
    final r = await rpc.call('git.diff', _p({'path': ?path, 'staged': staged}));
    return parseUnifiedDiff(r['diff'] is String ? r['diff'] as String : '');
  }

  Future<List<DiffFile>> diffHead({String? path}) async {
    final r = await rpc.call('git.diff_head', _p({'path': ?path}));
    return parseUnifiedDiff(r['diff'] is String ? r['diff'] as String : '');
  }

  Future<List<Commit>> log({int limit = 30}) async =>
      Commit.listFrom((await rpc.call('git.log', _p({'limit': limit})))['commits']);

  Future<List<Branch>> branches() async =>
      Branch.listFrom((await rpc.call('git.branches', _p()))['branches']);

  Future<void> stage(List<String> paths) => rpc.call('git.stage', _p({'paths': paths}));
  Future<void> unstage(List<String> paths) => rpc.call('git.unstage', _p({'paths': paths}));
  Future<void> discard(String path) => rpc.call('git.discard', _p({'path': path}));

  /// Returns the new commit hash.
  Future<String> commit(String message) async {
    final r = await rpc.call('git.commit', _p({'message': message}));
    return r['hash'] is String ? r['hash'] as String : '';
  }

  Future<void> checkout(String name) => rpc.call('git.checkout', _p({'name': name}));
  Future<void> createBranch(String name) => rpc.call('git.create_branch', _p({'name': name}));
}

/// Result of `fs.read`.
class FileContent {
  const FileContent({required this.path, required this.content, required this.size});
  final String path;
  final String content;
  final int size;

  factory FileContent.fromJson(Json j, String requested) => FileContent(
        path: j['path'] is String ? j['path'] as String : requested,
        content: j['content'] is String ? j['content'] as String : '',
        size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      );
}

final projectApiProvider = Provider.autoDispose.family<ProjectApi, ProjectKey>(
    (ref, k) => ProjectApi(rpcFor(ref, k.desktopId), k.workspaceId));

final gitStatusProvider = FutureProvider.autoDispose.family<GitStatus, ProjectKey>(
    (ref, k) => ref.watch(projectApiProvider(k)).status(),
    retry: (_, _) => null);

final diffHeadProvider = FutureProvider.autoDispose.family<List<DiffFile>, ProjectKey>(
    (ref, k) => ref.watch(projectApiProvider(k)).diffHead(),
    retry: (_, _) => null);

final gitLogProvider = FutureProvider.autoDispose.family<List<Commit>, ProjectKey>(
    (ref, k) => ref.watch(projectApiProvider(k)).log(),
    retry: (_, _) => null);

final gitBranchesProvider = FutureProvider.autoDispose.family<List<Branch>, ProjectKey>(
    (ref, k) => ref.watch(projectApiProvider(k)).branches(),
    retry: (_, _) => null);

/// After any write: the working tree may have changed.
void invalidateGit(WidgetRef ref, ProjectKey k) {
  ref.invalidate(gitStatusProvider(k));
  ref.invalidate(diffHeadProvider(k));
  ref.invalidate(gitLogProvider(k));
  ref.invalidate(gitBranchesProvider(k));
}
