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
        actions: [
          IconButton(
            tooltip: 'Agent usage',
            icon: const Icon(Icons.speed),
            onPressed: () => context.push('/d/$desktopId/usage'),
          ),
        ],
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
                  Text('JenderalCode ${o.hello.desktopVersion}',
                      style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  _TerminalsEntry(desktopId: desktopId),
                  const SizedBox(height: 20),
                  const Eyebrow('Projects'),
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
            Icon(Icons.folder_outlined, size: 20, color: cs.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;
    final on = ref.watch(capabilitiesProvider(desktopId)).terminal;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/d/$desktopId/t'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.terminal, size: 20, color: on ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Terminals',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(on ? 'Desktop tabs and shells opened from this phone' : allowOnDesktopHint,
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
