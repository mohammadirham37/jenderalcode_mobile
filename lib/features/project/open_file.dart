import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/rpc_client.dart';
import 'project_api.dart';

/// The file shown in the Editor tab, shared with the Files tab.
class OpenFileState {
  const OpenFileState({
    this.path,
    this.content = '',
    this.loading = false,
    this.error,
    this.dirty = false,
    this.saving = false,
    this.version = 0,
  });

  final String? path;

  /// Last loaded or saved content (the editor holds the live text).
  final String content;
  final bool loading;
  final String? error;
  final bool dirty;
  final bool saving;

  /// Bumped on every load so the editor recreates its controller.
  final int version;

  OpenFileState copyWith({
    Object? path = _keep,
    String? content,
    bool? loading,
    Object? error = _keep,
    bool? dirty,
    bool? saving,
    int? version,
  }) =>
      OpenFileState(
        path: path == _keep ? this.path : path as String?,
        content: content ?? this.content,
        loading: loading ?? this.loading,
        error: error == _keep ? this.error : error as String?,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        version: version ?? this.version,
      );
}

const _keep = Object();

String readableFileError(RpcError e) => switch (e.code) {
      'bad_request' => e.message.isNotEmpty
          ? e.message
          : 'This file cannot be opened here (binary, larger than 512 KiB, or sensitive).',
      _ => e.readable,
    };

class OpenFileController extends Notifier<OpenFileState> {
  OpenFileController(this.key);
  final ProjectKey key;
  int _gen = 0;

  @override
  OpenFileState build() => const OpenFileState();

  /// Loads [path]. Callers confirm discarding unsaved edits first.
  Future<void> open(String path) async {
    final gen = ++_gen;
    state = OpenFileState(path: path, loading: true, version: state.version + 1);
    try {
      final f = await ref.read(projectApiProvider(key)).read(path);
      if (!ref.mounted || gen != _gen) return;
      state = OpenFileState(path: path, content: f.content, version: state.version + 1);
    } on RpcError catch (e) {
      if (!ref.mounted || gen != _gen) return;
      state = OpenFileState(path: path, error: readableFileError(e), version: state.version + 1);
    }
  }

  Future<void> reload() async {
    final p = state.path;
    if (p != null) await open(p);
  }

  void setDirty(bool d) {
    if (state.dirty != d) state = state.copyWith(dirty: d);
  }

  /// Returns null on success, else a readable error.
  Future<String?> save(String content) async {
    final p = state.path;
    if (p == null || state.saving) return null;
    state = state.copyWith(saving: true);
    try {
      await ref.read(projectApiProvider(key)).write(p, content);
      if (ref.mounted) state = state.copyWith(saving: false, dirty: false, content: content);
      return null;
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(saving: false);
      return e.readable;
    }
  }

  void close() {
    _gen++;
    state = OpenFileState(version: state.version + 1);
  }

  /// A file or folder was deleted or renamed in the Files tab.
  void pathRemoved(String path) {
    final p = state.path;
    if (p != null && (p == path || p.startsWith('$path/'))) close();
  }
}

final openFileProvider = NotifierProvider.autoDispose
    .family<OpenFileController, OpenFileState, ProjectKey>(OpenFileController.new);
