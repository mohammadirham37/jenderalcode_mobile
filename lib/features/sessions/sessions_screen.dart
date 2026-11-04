import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../agents/agent_cli.dart';
import '../agents/agent_session_tile.dart';
import '../agents/new_session_sheet.dart';
import '../chat/composer_logic.dart';
import '../desktops/capabilities.dart';
import '../terminal/terminal_controller.dart';
import '../terminal/terminal_look.dart';
import 'sessions_providers.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({
    super.key,
    required this.desktopId,
    required this.workspaceId,
    required this.workspaceName,
  });
  final String desktopId;
  final String workspaceId;
  final String workspaceName;

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  bool _creating = false;

  WorkspaceKey get _key => (desktopId: widget.desktopId, workspaceId: widget.workspaceId);

  void _open(Session s) => context.push(
      '/d/${widget.desktopId}/s/${s.id}?title=${Uri.encodeQueryComponent(s.title)}');

  void _project(String tab) => context.push(
      '/d/${widget.desktopId}/w/${widget.workspaceId}/p?name=${Uri.encodeQueryComponent(widget.workspaceName)}&tab=$tab');

  Future<void> _new() async {
    final choice = await showNewSessionSheet(context, widget.desktopId);
    if (!mounted) return;
    switch (choice) {
      case NewChatChoice():
        await _newChat();
      case NewAgentChoice():
        await _newAgent(choice);
      case null:
        break;
    }
  }

  Future<void> _newAgent(NewAgentChoice c) async {
    final hub = ref.read(hubProvider);
    if (hub == null || !hub.isKnown(widget.desktopId)) return;
    final g = phoneGrid(context);
    setState(() => _creating = true);
    try {
      final t = await openAgentCli(
        rpc: hub.rpc(widget.desktopId),
        cli: c.cli,
        workspaceId: widget.workspaceId,
        cols: g.cols,
        rows: g.rows,
        resume: c.resume,
        bypass: c.bypass,
        confirmBypass: () => confirmDialog(
          context,
          title: 'Bypass permissions?',
          body: bypassConfirmText(c.cli.name),
          confirm: 'Continue',
          destructive: true,
        ),
      );
      if (t == null || !mounted) return;
      if (c.bypass && c.cli.hasBypass) ref.read(bypassTerminalsProvider.notifier).add(t.id);
      await _openTerminal(t);
    } on RpcError catch (e) {
      _snack(e.readable);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openTerminal(RemoteTerminal t) async {
    await context.push(
        '/d/${widget.desktopId}/t/${t.id}?title=${Uri.encodeQueryComponent(t.title)}');
    if (mounted) ref.invalidate(terminalsProvider(widget.desktopId));
  }

  Future<void> _closeTerminal(RemoteTerminal t) async {
    final ok = await confirmDialog(
      context,
      title: 'Close ${t.title.isEmpty ? 'agent' : t.title}?',
      body: 'This ends the agent CLI and everything running in its terminal.',
      confirm: 'Close',
      destructive: true,
    );
    final hub = ref.read(hubProvider);
    if (!ok || hub == null || !hub.isKnown(widget.desktopId)) return;
    try {
      await hub.rpc(widget.desktopId).call('terminal.close', {'terminal_id': t.id});
    } on RpcError catch (e) {
      _snack(e.readable);
    }
    ref.invalidate(terminalsProvider(widget.desktopId));
  }

  Future<void> _newChat() async {
    final hub = ref.read(hubProvider);
    if (hub == null || !hub.isKnown(widget.desktopId)) return;
    setState(() => _creating = true);
    try {
      final r = await hub
          .rpc(widget.desktopId)
          .call('session.new', {'workspace_id': widget.workspaceId});
      final s = Session.fromJson((r['session'] as Map).cast());
      ref.invalidate(sessionsProvider(_key));
      if (mounted) _open(s);
    } on RpcError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.readable)));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _rename(Session s) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: s.title),
    );
    final hub = ref.read(hubProvider);
    if (title == null || hub == null || !hub.isKnown(widget.desktopId)) return;
    try {
      await hub.rpc(widget.desktopId).call('session.rename', {'session_id': s.id, 'title': title});
      ref.invalidate(sessionsProvider(_key));
    } on RpcError catch (e) {
      _snack(e.readable);
    }
  }

  Future<void> _delete(Session s) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete session?',
      body: '"${s.title.isEmpty ? 'Untitled session' : s.title}" and its messages are deleted '
          'on the desktop. This cannot be undone.',
      confirm: 'Delete',
      destructive: true,
    );
    final hub = ref.read(hubProvider);
    if (!ok || hub == null || !hub.isKnown(widget.desktopId)) return;
    try {
      await hub.rpc(widget.desktopId).call('session.delete', {'session_id': s.id});
      ref.invalidate(sessionsProvider(_key));
    } on RpcError catch (e) {
      _snack(e.readable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sessionsProvider(_key));
    final caps = ref.watch(capabilitiesProvider(widget.desktopId));
    final agents = caps.terminal
        ? [
            for (final t in ref.watch(terminalsProvider(widget.desktopId)).value ??
                const <RemoteTerminal>[])
              if (t.isAgent && t.workspaceId == widget.workspaceId) t,
          ]
        : const <RemoteTerminal>[];
    Future<void> refresh() {
      if (caps.terminal) ref.invalidate(terminalsProvider(widget.desktopId));
      return ref.refresh(sessionsProvider(_key).future);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workspaceName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Changes, files, git',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => _project('changes'),
          ),
          IconButton(
            tooltip: 'Terminals',
            icon: const Icon(Icons.terminal),
            onPressed: () => _project('terminal'),
          ),
          IconButton(
            tooltip: 'Agent usage',
            icon: const Icon(Icons.speed),
            onPressed: () => context.push('/d/${widget.desktopId}/usage'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _new,
        icon: _creating
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('New session'),
      ),
      body: Column(children: [
        const ConnectionStrip(),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) =>
                ErrorPanel(message: e is RpcError ? e.readable : '$e', onRetry: refresh),
            data: (list) => RefreshIndicator(
              onRefresh: refresh,
              child: list.isEmpty && agents.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      EmptyPanel(title: 'No sessions', body: 'Start one with "New session".'),
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      children: [
                        if (agents.isNotEmpty) ...[
                          const Eyebrow('Agent CLI sessions'),
                          const SizedBox(height: 8),
                          for (final t in agents) ...[
                            AgentSessionTile(
                              t: t,
                              onTap: () => _openTerminal(t),
                              onClose: t.isRemote ? () => _closeTerminal(t) : null,
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 12),
                          const Eyebrow('JenderalCode chats'),
                          const SizedBox(height: 8),
                        ],
                        for (final s in list) ...[
                          _SessionTile(
                            s: s,
                            onTap: () => _open(s),
                            onRename: () => _rename(s),
                            onDelete: () => _delete(s),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.s,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });
  final Session s;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = [
      if (s.modelName != null) s.modelName!,
      '${s.messageCount} msg',
      relativeTime(s.updatedAt),
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(s.title.isEmpty ? 'Untitled session' : s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (s.isYolo)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('FULL ACCESS', style: mono(context, size: 10, color: cs.error)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(meta, style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'Session actions',
              icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(
                    value: 'delete', child: Text('Delete', style: TextStyle(color: cs.error))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final err = validateTitle(_c.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: _c,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _submit, child: const Text('Rename')),
        ],
      );
}
