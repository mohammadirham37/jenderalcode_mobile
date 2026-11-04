import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'agent_cli.dart';

/// Subscription usage of the agent CLIs (`agent_clis.usage`), like the
/// desktop's Gauge button. Read-only.
class AgentUsageScreen extends ConsumerWidget {
  const AgentUsageScreen({super.key, required this.desktopId});
  final String desktopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(agentUsageProvider(desktopId));
    Future<void> refresh() => ref.refresh(agentUsageProvider(desktopId).future);
    return Scaffold(
      appBar: AppBar(title: const Text('Agent usage')),
      body: Column(children: [
        const ConnectionStrip(),
        Expanded(
          child: data.when(
            loading: () => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 12),
                Text('Asking each CLI…', style: mono(context, size: 11.5)),
              ]),
            ),
            error: (e, _) => ErrorPanel(message: e is RpcError ? e.readable : '$e', onRetry: refresh),
            data: (list) => RefreshIndicator(
              onRefresh: refresh,
              child: list.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      EmptyPanel(title: 'No reports', body: 'No agent CLIs are enabled on the desktop.'),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ReportCard(r: list[i]),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.r});
  final AgentUsageReport r;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = r.status == AgentUsageStatus.ok;
    final statusColor = ok
        ? cs.primary
        : r.status == AgentUsageStatus.error || r.status == AgentUsageStatus.expired
            ? cs.error
            : cs.onSurfaceVariant;
    final meta = [?r.plan, ?r.account].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: statusColor.withValues(alpha: 0.6)),
              ),
              child: Text(r.status.label.toUpperCase(), style: mono(context, size: 10, color: statusColor)),
            ),
          ]),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(meta, style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
          ],
          for (final w in r.windows) ...[const SizedBox(height: 12), _WindowBar(w: w)],
          if (r.note != null) ...[
            const SizedBox(height: 10),
            Text(r.note!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.w});
  final UsageWindow w;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = w.usedPercent;
    final f = p == null ? null : (p / 100).clamp(0.0, 1.0);
    final color = f == null
        ? cs.onSurfaceVariant
        : f >= 0.9
            ? cs.error
            : f >= 0.7
                ? const Color(0xFFD9A441)
                : cs.primary;
    final resets = resetsIn(w.resetsAt);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(w.label, style: const TextStyle(fontSize: 13))),
        if (p != null) Text('${p.toStringAsFixed(p % 1 == 0 ? 0 : 1)}%', style: mono(context, size: 12, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: f ?? 0,
          minHeight: 5,
          color: color,
          backgroundColor: cs.surfaceContainerHigh,
        ),
      ),
      if (resets != null || w.detail != null) ...[
        const SizedBox(height: 3),
        Text([?resets, ?w.detail].join(' · '), style: mono(context, size: 11, color: cs.onSurfaceVariant)),
      ],
    ]);
  }
}
