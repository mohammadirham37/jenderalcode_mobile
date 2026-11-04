import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import 'gating.dart';
import 'open_file.dart';
import 'project_api.dart';
import 'project_widgets.dart';

class _Row {
  const _Row(this.entry, this.depth);
  final FileEntry entry;
  final int depth;
}

/// Project tree from `fs.list`, loaded one folder at a time.
class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key, required this.projectKey, required this.onOpen});
  final ProjectKey projectKey;

  /// Opens a file in the Editor tab (the caller guards unsaved edits).
  final void Function(String path) onOpen;

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<FilesTab> {
  final _children = <String, List<FileEntry>>{};
  final _errors = <String, String>{};
  final _loading = <String>{};
  final _expanded = <String>{};
  bool _showHidden = false;

  ProjectApi get _api => ref.read(projectApiProvider(widget.projectKey));

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String dir) async {
    setState(() {
      _loading.add(dir);
      _errors.remove(dir);
    });
    try {
      final list = await _api.list(dir, showHidden: _showHidden);
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (mounted) setState(() => _children[dir] = list);
    } on RpcError catch (e) {
      if (mounted) setState(() => _errors[dir] = e.readable);
    } finally {
      if (mounted) setState(() => _loading.remove(dir));
    }
  }

  Future<void> _refreshAll() async {
    final dirs = ['', ..._expanded];
    _children.clear();
    await Future.wait(dirs.map(_load));
  }

  void _toggle(FileEntry e) {
    if (_expanded.remove(e.path)) {
      setState(() {});
      return;
    }
    setState(() => _expanded.add(e.path));
    if (!_children.containsKey(e.path)) _load(e.path);
  }

  List<_Row> _rows() {
    final out = <_Row>[];
    void walk(String dir, int depth) {
      for (final e in _children[dir] ?? const <FileEntry>[]) {
        out.add(_Row(e, depth));
        if (e.isDir && _expanded.contains(e.path)) walk(e.path, depth + 1);
      }
    }

    walk('', 0);
    return out;
  }

  Future<String?> _askName({required String title, String initial = '', String hint = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(builder: (ctx, setLocal) {
          void submit() {
            final v = validateRelativePath(c.text);
            if (v != null) {
              setLocal(() => err = v);
              return;
            }
            Navigator.pop(ctx, c.text.trim());
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: c,
              autofocus: true,
              autocorrect: false,
              style: mono(ctx, size: 13),
              decoration: InputDecoration(hintText: hint, errorText: err),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: submit, child: const Text('OK')),
            ],
          );
        });
      },
    );
  }

  Future<void> _write(Future<void> Function() call, {required String done}) async {
    final caps = ref.read(capabilitiesProvider(widget.projectKey.desktopId));
    final err = await performWrite(caps, call);
    if (!mounted) return;
    showSnack(context, err == null ? done : writeErrorText(err));
    if (err == null) invalidateGit(ref, widget.projectKey);
  }

  Future<void> _create(String dir, {required bool isDir}) async {
    final name = await _askName(
      title: isDir ? 'New folder' : 'New file',
      hint: isDir ? 'folder name' : 'file name, e.g. src/notes.md',
    );
    if (name == null) return;
    final path = joinPath(dir, name);
    await _write(() => _api.create(path, isDir: isDir), done: 'Created $path');
    if (!mounted) return;
    if (dir.isNotEmpty) _expanded.add(dir);
    await _load(dir);
    // A nested name like "a/b.txt" creates folders too.
    if (name.contains('/')) await _refreshAll();
    if (!isDir && mounted) widget.onOpen(path);
  }

  Future<void> _rename(FileEntry e) async {
    final name = await _askName(title: 'Rename', initial: e.name);
    if (name == null || name == e.name) return;
    final dir = parentOf(e.path);
    final to = joinPath(dir, name);
    await _write(() => _api.rename(e.path, to), done: 'Renamed to $to');
    if (!mounted) return;
    ref.read(openFileProvider(widget.projectKey).notifier).pathRemoved(e.path);
    _forget(e.path);
    await _load(dir);
  }

  Future<void> _delete(FileEntry e) async {
    final ok = await confirmDialog(
      context,
      title: e.isDir ? 'Delete folder?' : 'Delete file?',
      body: e.isDir
          ? '${e.path} and everything in it will be deleted on the desktop.'
          : '${e.path} will be deleted on the desktop.',
      confirm: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final dir = parentOf(e.path);
    await _write(() => _api.delete(e.path), done: 'Deleted ${e.path}');
    if (!mounted) return;
    ref.read(openFileProvider(widget.projectKey).notifier).pathRemoved(e.path);
    _forget(e.path);
    await _load(dir);
  }

  void _forget(String path) {
    _children.removeWhere((k, _) => k == path || k.startsWith('$path/'));
    _expanded.removeWhere((k) => k == path || k.startsWith('$path/'));
  }

  void _menu(FileEntry e, bool edit) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(e.path, style: mono(ctx, size: 12)),
          ),
          if (!edit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(allowOnDesktopHint,
                  style: mono(ctx, size: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
          if (e.isDir) ...[
            ListTile(
              enabled: edit,
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New file here'),
              onTap: () {
                Navigator.pop(ctx);
                _create(e.path, isDir: false);
              },
            ),
            ListTile(
              enabled: edit,
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder here'),
              onTap: () {
                Navigator.pop(ctx);
                _create(e.path, isDir: true);
              },
            ),
          ],
          ListTile(
            enabled: edit,
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(ctx);
              _rename(e);
            },
          ),
          ListTile(
            enabled: edit,
            leading: Icon(Icons.delete_outline, color: edit ? Theme.of(ctx).colorScheme.error : null),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(ctx);
              _delete(e);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caps = ref.watch(capabilitiesProvider(widget.projectKey.desktopId));
    final open = ref.watch(openFileProvider(widget.projectKey)).path;
    final rows = _rows();
    final rootLoading = _loading.contains('') && !_children.containsKey('');

    final toolbar = Container(
      padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      child: Row(children: [
        const Eyebrow('Files'),
        const Spacer(),
        IconButton(
          tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
          visualDensity: VisualDensity.compact,
          icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off_outlined, size: 20),
          onPressed: () {
            setState(() => _showHidden = !_showHidden);
            _refreshAll();
          },
        ),
        IconButton(
          tooltip: 'New file',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.note_add_outlined, size: 20),
          onPressed: whenEditable(caps, () => _create('', isDir: false)),
        ),
        IconButton(
          tooltip: 'New folder',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.create_new_folder_outlined, size: 20),
          onPressed: whenEditable(caps, () => _create('', isDir: true)),
        ),
      ]),
    );

    Widget body;
    if (rootLoading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_errors[''] != null && !_children.containsKey('')) {
      body = ErrorPanel(message: _errors['']!, onRetry: () => _load(''));
    } else if (rows.isEmpty) {
      body = ListView(children: const [
        SizedBox(height: 100),
        EmptyPanel(title: 'Empty folder'),
      ]);
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          final e = r.entry;
          final expanded = _expanded.contains(e.path);
          final selected = e.path == open;
          final err = _errors[e.path];
          return InkWell(
            onTap: () => e.isDir ? _toggle(e) : widget.onOpen(e.path),
            onLongPress: () => _menu(e, caps.edit),
            child: Container(
              color: selected ? cs.primary.withValues(alpha: 0.10) : null,
              padding: EdgeInsets.fromLTRB(10.0 + r.depth * 16, 7, 4, 7),
              child: Row(children: [
                SizedBox(
                  width: 18,
                  child: e.isDir
                      ? (_loading.contains(e.path)
                          ? const SizedBox(
                              width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                          : Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                              size: 18, color: cs.onSurfaceVariant))
                      : null,
                ),
                const SizedBox(width: 4),
                Icon(
                  e.isDir ? (expanded ? Icons.folder_open_outlined : Icons.folder_outlined) : Icons.description_outlined,
                  size: 17,
                  color: e.isDir ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(err != null ? '${e.name}  ($err)' : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context,
                          size: 12.5, color: err != null ? cs.error : (selected ? cs.primary : cs.onSurface))),
                ),
                if (!e.isDir && e.size != null)
                  Text(_size(e.size!), style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'More',
                  icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                  onPressed: () => _menu(e, caps.edit),
                ),
              ]),
            ),
          );
        },
      );
    }

    return Column(children: [
      if (!caps.edit) const EditHint(),
      toolbar,
      Expanded(child: RefreshIndicator(onRefresh: _refreshAll, child: body)),
    ]);
  }
}

String _size(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}
