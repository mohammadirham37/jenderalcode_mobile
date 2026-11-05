import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import '../desktops/desktops_controller.dart';
import 'sessions_providers.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';

class WorkspacesScreen extends ConsumerWidget {
  const WorkspacesScreen({super.key, required this.desktopId});
  final String desktopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final desktop = ref
        .watch(desktopsProvider)
        .value
        ?.where((d) => d.deviceId == desktopId)
        .firstOrNull;
    final online = ref.watch(presenceProvider).value?[desktopId] ?? false;
    final data = ref.watch(desktopOverviewProvider(desktopId));
    Future<void> refresh() => ref.refresh(desktopOverviewProvider(desktopId).future);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          OnlineDot(online: online),
          const SizedBox(width: 10),
          Expanded(child: Text(desktop?.name ?? 'Desktop', overflow: TextOverflow.ellipsis)),
        ]),
        actions: const [HelpButton(topic: HelpTopic.chat)],
      ),
      body: Column(children: [
        const ConnectionStrip(),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => ErrorPanel(
              message: e is RpcError ? e.readable : '$e',
              onRetry: refresh,
            ),
            data: (o) => RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (!online) ...[
                    const _OfflineNote(),
                    const SizedBox(height: 12),
                  ],
                  Text('JenderalCode ${o.hello.desktopVersion}',
                      style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: _TerminalsEntry(desktopId: desktopId)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickCard(
                          icon: Icons.speed,
                          title: 'Agent usage',
                          body: 'Claude Code, Codex and other quotas',
                          onTap: () => context.push('/d/$desktopId/usage'),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  _QuickCard(
                    icon: Icons.public,
                    title: 'Browser',
                    body: 'Open a dev server running on the desktop (localhost)',
                    dim: !ref.watch(capabilitiesProvider(desktopId)).browser,
                    onTap: () => context.push('/d/$desktopId/browser'),
                  ),
                  const SizedBox(height: 22),
                  const Eyebrow('Projects'),
                  const SizedBox(height: 2),
                  Text('Pick a project to chat, run agents or view files.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  if (o.workspaces.isEmpty)
                    const EmptyPanel(
                        title: 'No projects', body: 'Open a folder on the desktop first.'),
                  for (final w in o.workspaces) ...[
                    _WorkspaceTile(
                      w: w,
                      onTap: () => context.push(
                          '/d/$desktopId/w/${w.id}?name=${Uri.encodeQueryComponent(w.name)}'),
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

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({required this.w, required this.onTap});
  final Workspace w;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(Icons.folder_outlined, size: 21, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(w.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (w.isGitRepo) ...[
                    const SizedBox(width: 8),
                    Text('git', style: mono(context, size: 10.5, color: cs.primary)),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(w.rootPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _TerminalsEntry extends ConsumerWidget {
  const _TerminalsEntry({required this.desktopId});
  final String desktopId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(capabilitiesProvider(desktopId)).terminal;
    return _QuickCard(
      icon: Icons.terminal,
      title: 'Terminals',
      body: on ? 'Desktop tabs and new shells' : allowOnDesktopHint,
      dim: !on,
      onTap: () => context.push('/d/$desktopId/t'),
    );
  }
}

/// A square shortcut card (Terminals, Agent usage).
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.dim = false,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool dim;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 22, color: dim ? cs.onSurfaceVariant : cs.primary),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(body, style: TextStyle(fontSize: 12, height: 1.35, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Shown while the desktop is offline: what to check.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.cloud_off_outlined, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Desktop is offline', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Open JenderalCode on the computer and keep Remote control on.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
          ]),
        ),
        TextButton(
          onPressed: () => openHelp(context, HelpTopic.trouble),
          child: const Text('Help'),
        ),
      ]),
    );
  }
}
