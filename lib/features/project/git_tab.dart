import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import 'changes_tab.dart';
import 'gating.dart';
import 'git_model.dart';
import 'project_api.dart';
import 'project_widgets.dart';

/// Git panel: status (staged / unstaged), stage, unstage, discard, commit,
/// branches and log (§6.8). Push/pull stay in the terminal.
class GitTab extends ConsumerStatefulWidget {
  const GitTab({super.key, required this.projectKey});
  final ProjectKey projectKey;

  @override
  ConsumerState<GitTab> createState() => _GitTabState();
}

class _GitTabState extends ConsumerState<GitTab> {
  final _message = TextEditingController();
  final _busy = <String>{};

  ProjectKey get _k => widget.projectKey;
  ProjectApi get _api => ref.read(projectApiProvider(_k));

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<bool> _write(String tag, Future<void> Function() call, {String? done}) async {
    if (_busy.contains(tag)) return false;
    setState(() => _busy.add(tag));
    final caps = ref.read(capabilitiesProvider(_k.desktopId));
    final err = await performWrite(caps, call);
    if (!mounted) return false;
    setState(() => _busy.remove(tag));
    if (err != null) {
      showSnack(context, writeErrorText(err));
    } else if (done != null) {
      showSnack(context, done);
    }
    invalidateGit(ref, _k);
    return err == null;
  }

  Future<void> _discard(FileStatus f) async {
    if (f.worktree == StatusKind.untracked) {
      // git.discard only restores tracked files (docs/protocol.md §6.8);
      // delete an untracked file from the Files tab instead.
      showSnack(context, '${f.path} is untracked. Delete it from the Files tab instead.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Discard changes?',
      body: 'Unstaged changes to ${f.path} will be lost. This cannot be undone.',
      confirm: 'Discard',
      destructive: true,
    );
    if (ok) await _write('discard:${f.path}', () => _api.discard(f.path), done: 'Discarded ${f.path}');
  }

  Future<void> _commit() async {
    final msg = _message.text.trim();
    if (msg.isEmpty) return;
    var hash = '';
    final ok = await _write('commit', () async => hash = await _api.commit(msg));
    if (!ok || !mounted) return;
    _message.clear();
    showSnack(context, 'Committed ${hash.length > 7 ? hash.substring(0, 7) : hash}');
  }

  void _showDiff(FileStatus f, {required bool staged}) => DiffScreen.push(
        context,
        title: '${f.path}${staged ? ' (staged)' : ''}',
        load: () => _api.diff(path: f.path, staged: staged),
      );

  Future<void> _branches() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _BranchesSheet(projectKey: _k),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caps = ref.watch(capabilitiesProvider(_k.desktopId));
    final status = ref.watch(gitStatusProvider(_k));
    Future<void> refresh() async {
      invalidateGit(ref, _k);
      await ref.read(gitStatusProvider(_k).future);
    }

    return status.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => RefreshIndicator(onRefresh: refresh, child: gitErrorPanel(context, e, refresh)),
      data: (st) {
        final g = st.groups;
        return Column(children: [
          if (!caps.edit) const EditHint(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  // Branch
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _branches,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(Icons.call_split, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(st.branch ?? 'detached HEAD',
                                overflow: TextOverflow.ellipsis,
                                style: mono(context, size: 13, weight: FontWeight.w600)),
                          ),
                          Text('Branches', style: mono(context, size: 11, color: cs.onSurfaceVariant)),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Commit
                  const Eyebrow('Commit'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _message,
                    enabled: caps.edit,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: caps.edit ? 'Commit message' : allowOnDesktopHint,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: caps.edit &&
                            g.staged.isNotEmpty &&
                            _message.text.trim().isNotEmpty &&
                            !_busy.contains('commit')
                        ? _commit
                        : null,
                    icon: _busy.contains('commit')
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 18),
                    label: Text(g.staged.isEmpty
                        ? 'Stage files to commit'
                        : 'Commit ${g.staged.length} file${g.staged.length == 1 ? '' : 's'}'),
                  ),
                  const SizedBox(height: 20),
                  if (g.isClean)
                    const EmptyPanel(title: 'Working tree clean'),
                  if (g.staged.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Staged (${g.staged.length})',
                      action: 'Unstage all',
                      onAction: whenEditable(caps,
                          () => _write('unstage:*', () => _api.unstage([for (final f in g.staged) f.path]))),
                    ),
                    for (final f in g.staged)
                      _StatusRow(
                        file: f,
                        staged: true,
                        busy: _busy.contains('unstage:${f.path}'),
                        onTap: () => _showDiff(f, staged: true),
                        actions: [
                          _RowAction(
                            icon: Icons.remove,
                            tooltip: 'Unstage',
                            onPressed: whenEditable(
                                caps, () => _write('unstage:${f.path}', () => _api.unstage([f.path]))),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (g.unstaged.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Changes (${g.unstaged.length})',
                      action: 'Stage all',
                      onAction: whenEditable(caps,
                          () => _write('stage:*', () => _api.stage([for (final f in g.unstaged) f.path]))),
                    ),
                    for (final f in g.unstaged)
                      _StatusRow(
                        file: f,
                        staged: false,
                        busy: _busy.contains('stage:${f.path}') || _busy.contains('discard:${f.path}'),
                        onTap: () => _showDiff(f, staged: false),
                        actions: [
                          _RowAction(
                            icon: Icons.undo,
                            tooltip: 'Discard',
                            color: cs.error,
                            onPressed: whenEditable(caps, () => _discard(f)),
                          ),
                          _RowAction(
                            icon: Icons.add,
                            tooltip: 'Stage',
                            onPressed: whenEditable(
                                caps, () => _write('stage:${f.path}', () => _api.stage([f.path]))),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                  ],
                  const Eyebrow('History'),
                  const SizedBox(height: 6),
                  _LogList(projectKey: _k),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, this.onAction});
  final String title;
  final String action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(children: [
        Eyebrow(title),
        const Spacer(),
        TextButton(onPressed: onAction, child: Text(action, style: const TextStyle(fontSize: 12.5))),
      ]);
}

class _RowAction {
  const _RowAction({required this.icon, required this.tooltip, this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.file,
    required this.staged,
    required this.onTap,
    required this.actions,
    this.busy = false,
  });
  final FileStatus file;
  final bool staged;
  final VoidCallback onTap;
  final List<_RowAction> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final k = displayKind(file, staged: staged);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 20,
            child: Text(k.letter,
                textAlign: TextAlign.center,
                style: mono(context, size: 12.5, color: statusColor(context, k), weight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 12.5, color: cs.onSurface)),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            for (final a in actions)
              IconButton(
                tooltip: a.tooltip,
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                color: a.color,
                icon: Icon(a.icon),
                onPressed: a.onPressed,
              ),
        ]),
      ),
    );
  }
}

class _LogList extends ConsumerWidget {
  const _LogList({required this.projectKey});
  final ProjectKey projectKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(gitLogProvider(projectKey)).when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('$e', style: TextStyle(color: cs.error)),
          data: (commits) => commits.isEmpty
              ? Text('No commits yet.', style: mono(context, size: 12, color: cs.onSurfaceVariant))
              : Column(children: [
                  for (final c in commits)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.shortHash.isNotEmpty ? c.shortHash : shortId(c.hash),
                            style: mono(context, size: 11.5, color: cs.primary)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text('${c.author} · ${relativeTime(c.timestampMs)}',
                                style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
                          ]),
                        ),
                      ]),
                    ),
                ]),
        );
  }
}

class _BranchesSheet extends ConsumerStatefulWidget {
  const _BranchesSheet({required this.projectKey});
  final ProjectKey projectKey;
  @override
  ConsumerState<_BranchesSheet> createState() => _BranchesSheetState();
}

class _BranchesSheetState extends ConsumerState<_BranchesSheet> {
  final _name = TextEditingController();
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(String tag, Future<void> Function() call) async {
    setState(() {
      _busy = tag;
      _error = null;
    });
    final caps = ref.read(capabilitiesProvider(widget.projectKey.desktopId));
    final err = await performWrite(caps, call);
    if (!mounted) return;
    invalidateGit(ref, widget.projectKey);
    setState(() {
      _busy = null;
      _error = err == null ? null : writeErrorText(err);
    });
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caps = ref.watch(capabilitiesProvider(widget.projectKey.desktopId));
    final api = ref.read(projectApiProvider(widget.projectKey));
    final branches = ref.watch(gitBranchesProvider(widget.projectKey));
    final validName = RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(_name.text.trim()) &&
        !_name.text.trim().startsWith('-');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Eyebrow('Branches'),
              if (!caps.edit) ...[
                const SizedBox(height: 4),
                Text(allowOnDesktopHint, style: mono(context, size: 11, color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: branches.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => Text('$e', style: TextStyle(color: cs.error)),
                  data: (list) => ListView(shrinkWrap: true, children: [
                    for (final b in list)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(b.current ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18, color: b.current ? cs.primary : cs.onSurfaceVariant),
                        title: Text(b.name, style: mono(context, size: 13)),
                        trailing: _busy == 'checkout:${b.name}'
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                        onTap: b.current || !caps.edit || _busy != null
                            ? null
                            : () => _run('checkout:${b.name}', () => api.checkout(b.name)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: caps.edit,
                    autocorrect: false,
                    style: mono(context, size: 13),
                    decoration: const InputDecoration(hintText: 'new-branch-name'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: caps.edit && validName && _busy == null
                      ? () => _run('create', () => api.createBranch(_name.text.trim()))
                      : null,
                  child: const Text('Create & switch'),
                ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
