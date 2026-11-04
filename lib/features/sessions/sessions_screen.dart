import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
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

  Future<void> _new() async {
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

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sessionsProvider(_key));
    Future<void> refresh() => ref.refresh(sessionsProvider(_key).future);
    return Scaffold(
      appBar: AppBar(title: Text(widget.workspaceName, overflow: TextOverflow.ellipsis)),
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
              child: list.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      EmptyPanel(title: 'No sessions', body: 'Start one with "New session".'),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SessionTile(s: list[i], onTap: () => _open(list[i])),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.s, required this.onTap});
  final Session s;
  final VoidCallback onTap;
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
          padding: const EdgeInsets.all(14),
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
      ),
    );
  }
}
