import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import '../sessions/sessions_providers.dart';
import 'terminal_controller.dart';
import 'terminal_look.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';

/// Full page: every terminal on one desktop.
class TerminalsScreen extends StatelessWidget {
  const TerminalsScreen({super.key, required this.desktopId});
  final String desktopId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Terminals'),
          actions: const [HelpButton(topic: HelpTopic.terminals)],
        ),
        body: Column(children: [
          const ConnectionStrip(),
          Expanded(child: TerminalsView(desktopId: desktopId)),
        ]),
      );
}

/// `terminal.list` grouped by origin, with "New terminal". With
/// [workspaceId], only that project's terminals are listed and new ones open
/// there.
class TerminalsView extends ConsumerStatefulWidget {
  const TerminalsView({super.key, required this.desktopId, this.workspaceId});
  final String desktopId;
  final String? workspaceId;

  @override
  ConsumerState<TerminalsView> createState() => _TerminalsViewState();
}

class _TerminalsViewState extends ConsumerState<TerminalsView> {
  bool _opening = false;

  Future<void> _refresh() => ref.refresh(terminalsProvider(widget.desktopId).future);

  Future<void> _show(RemoteTerminal t) async {
    await context.push(
        '/d/${widget.desktopId}/t/${t.id}?title=${Uri.encodeQueryComponent(t.title)}');
    if (mounted) ref.invalidate(terminalsProvider(widget.desktopId));
  }

  Future<String?> _pickWorkspace() async {
    if (widget.workspaceId != null) return widget.workspaceId;
    final List<Workspace> list;
    try {
      list = (await ref.read(desktopOverviewProvider(widget.desktopId).future)).workspaces;
    } on RpcError catch (e) {
      _snack(e.readable);
      return null;
    }
    if (!mounted) return null;
    if (list.isEmpty) {
      _snack('No projects on the desktop. Open a folder there first.');
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Eyebrow('Open a shell in'),
          ),
          for (final w in list)
            ListTile(
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(w.name),
              subtitle: Text(w.rootPath,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(c, size: 11)),
              onTap: () => Navigator.pop(c, w.id),
            ),
        ]),
      ),
    );
  }

  Future<void> _new() async {
    final hub = ref.read(hubProvider);
    if (hub == null || !hub.isKnown(widget.desktopId)) return;
    final wid = await _pickWorkspace();
    if (wid == null || !mounted) return;
    final g = phoneGrid(context);
    setState(() => _opening = true);
    try {
      final t = await openTerminal(hub.rpc(widget.desktopId), wid, g.cols, g.rows);
      if (mounted) await _show(t);
    } on RpcError catch (e) {
      _snack(e.readable);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider(widget.desktopId));
    if (!caps.terminal) {
      return const EmptyPanel(
        title: 'Terminal is off',
        body: 'The desktop does not allow terminals from the phone. $allowOnDesktopHint.',
      );
    }
    final data = ref.watch(terminalsProvider(widget.desktopId));
    final names = {
      for (final w in ref.watch(desktopOverviewProvider(widget.desktopId)).value?.workspaces ??
          const <Workspace>[])
        w.id: w.name,
    };
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => ErrorPanel(message: e is RpcError ? e.readable : '$e', onRetry: _refresh),
      data: (all) {
        final list = widget.workspaceId == null
            ? all
            : [for (final t in all) if (t.workspaceId == widget.workspaceId) t];
        final desktop = [for (final t in list) if (!t.isRemote) t];
        final phone = [for (final t in list) if (t.isRemote) t];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _opening ? null : _new,
                  icon: _opening
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add, size: 18),
                  label: const Text('New terminal'),
                ),
              ),
              const SizedBox(height: 20),
              const Eyebrow('On the desktop'),
              const SizedBox(height: 8),
              if (desktop.isEmpty) _none(context, 'No terminal or agent tabs open on the desktop.'),
              for (final t in desktop) ...[
                _TerminalTile(t: t, project: names[t.workspaceId], onTap: () => _show(t)),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              const Eyebrow('Opened from this phone'),
              const SizedBox(height: 8),
              if (phone.isEmpty) _none(context, 'None yet. Up to 6 per desktop, agent sessions included.'),
              for (final t in phone) ...[
                _TerminalTile(t: t, project: names[t.workspaceId], onTap: () => _show(t)),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _none(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      );
}

class _TerminalTile extends StatelessWidget {
  const _TerminalTile({required this.t, required this.project, required this.onTap});
  final RemoteTerminal t;
  final String? project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = [
      t.isAgent ? 'agent' : 'shell',
      ?project,
      '${t.cols}×${t.rows}',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(t.isAgent ? Icons.smart_toy_outlined : Icons.terminal, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title.isEmpty ? (t.isAgent ? 'Agent' : 'Shell') : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(meta, style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
