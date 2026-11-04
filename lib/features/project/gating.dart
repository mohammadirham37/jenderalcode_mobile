import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Writing actions in the project panel need `capabilities.edit` (§6.5).
bool canEdit(Capabilities caps) => caps.edit;

/// [action] when editing is allowed, else null (a disabled button).
T? whenEditable<T extends Function>(Capabilities caps, T action) =>
    caps.edit ? action : null;

/// Runs a writing call only when the desktop allows edits. Returns null on
/// success, the error otherwise; `not_allowed` without sending when [caps]
/// says no.
Future<RpcError?> performWrite(Capabilities caps, Future<void> Function() call) async {
  if (!caps.edit) return const RpcError('not_allowed');
  try {
    await call();
    return null;
  } on RpcError catch (e) {
    return e;
  } catch (e) {
    return RpcError('internal', '$e');
  }
}

/// Validates a relative path typed by the user for create/rename. Returns an
/// error text, or null when it looks fine. The desktop checks again.
String? validateRelativePath(String p) {
  final t = p.trim();
  if (t.isEmpty) return 'Enter a name.';
  if (t.startsWith('/') || t.startsWith('\\')) return 'Use a path inside the project.';
  for (final seg in t.split(RegExp(r'[/\\]'))) {
    if (seg.isEmpty) return 'Empty path segment.';
    if (seg == '..' || seg == '.') return 'Use a path inside the project.';
  }
  return null;
}

String joinPath(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

String baseName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}
