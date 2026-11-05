import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import 'chat_catalog.dart';
import 'composer_logic.dart';

/// Agent, model and context meter above the composer.
class ChatToolbar extends StatelessWidget {
  const ChatToolbar({
    super.key,
    required this.agentLabel,
    required this.modelLabel,
    required this.onAgent,
    required this.onModel,
    required this.lastInput,
    required this.contextWindow,
    this.busy = false,
  });
  final String agentLabel;
  final String modelLabel;
  final VoidCallback? onAgent;
  final VoidCallback? onModel;
  final int? lastInput;
  final int? contextWindow;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Row(children: [
          Flexible(flex: 2, child: _Pill(icon: Icons.smart_toy_outlined, label: agentLabel, onTap: onAgent)),
          const SizedBox(width: 6),
          Flexible(flex: 3, child: _Pill(icon: Icons.memory, label: modelLabel, onTap: onModel)),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
          const Spacer(),
          if (lastInput != null) ContextMeter(lastInput: lastInput!, contextWindow: contextWindow),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 11.5, color: cs.onSurface)),
          ),
          Icon(Icons.arrow_drop_down, size: 16, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// `last_input / context_window`, like the desktop's ContextMeter.
class ContextMeter extends StatelessWidget {
  const ContextMeter({super.key, required this.lastInput, required this.contextWindow});
  final int lastInput;
  final int? contextWindow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = contextFraction(lastInput, contextWindow);
    final color = f == null
        ? cs.onSurfaceVariant
        : f >= 0.9
            ? cs.error
            : f >= 0.7
                ? const Color(0xFFD9A441)
                : cs.primary;
    final text = contextWindow == null
        ? compactTokens(lastInput)
        : '${compactTokens(lastInput)}/${compactTokens(contextWindow!)}';
    return Tooltip(
      message: f == null ? 'Context: $lastInput tokens' : 'Context ${(f * 100).round()}% full',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (f != null)
          SizedBox(
            width: 34,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 4,
                color: color,
                backgroundColor: cs.surfaceContainerHigh,
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text(text, style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Agent profiles from `agents.list`. Returns the picked id.
Future<String?> showAgentSheet(BuildContext context, String desktopId, String? current) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AgentSheet(desktopId: desktopId, current: current),
    );

class _AgentSheet extends ConsumerWidget {
  const _AgentSheet({required this.desktopId, required this.current});
  final String desktopId;
  final String? current;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(agentsProvider(desktopId));
    return _SheetFrame(
      title: 'Agent',
      child: data.when(
        loading: () => const _SheetLoading(),
        error: (e, _) => ErrorPanel(
            message: e is RpcError ? e.readable : '$e',
            onRetry: () => ref.invalidate(agentsProvider(desktopId))),
        data: (list) => list.isEmpty
            ? const EmptyPanel(title: 'No agents')
            : ListView(shrinkWrap: true, children: [
                for (final a in list)
                  ListTile(
                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [a.modeLabel, if (a.builtIn) 'built-in'].join(' · '),
                      style: mono(context, size: 11, color: cs.onSurfaceVariant),
                    ),
                    trailing: a.id == current ? Icon(Icons.check, color: cs.primary) : null,
                    onTap: a.id == current ? null : () => Navigator.pop(context, a.id),
                  ),
              ]),
      ),
    );
  }
}

/// Models from `models.list`, grouped by provider. Returns the picked model.
Future<Model?> showModelSheet(
        BuildContext context, String desktopId, String? providerId, String? modelName) =>
    showModalBottomSheet<Model>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ModelSheet(desktopId: desktopId, providerId: providerId, modelName: modelName),
    );

class _ModelSheet extends ConsumerWidget {
  const _ModelSheet({required this.desktopId, required this.providerId, required this.modelName});
  final String desktopId;
  final String? providerId;
  final String? modelName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(modelsProvider(desktopId));
    return _SheetFrame(
      title: 'Model',
      child: data.when(
        loading: () => const _SheetLoading(),
        error: (e, _) => ErrorPanel(
            message: e is RpcError ? e.readable : '$e',
            onRetry: () => ref.invalidate(modelsProvider(desktopId))),
        data: (cat) {
          final groups = cat.grouped;
          if (groups.isEmpty) {
            return const EmptyPanel(title: 'No models', body: 'Enable a provider on the desktop.');
          }
          return ListView(shrinkWrap: true, children: [
            for (final (p, models) in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Eyebrow(p.name.isEmpty ? p.id : p.name),
              ),
              for (final m in models)
                ListTile(
                  dense: true,
                  title: Text(m.label),
                  subtitle: Text(
                    [
                      m.name,
                      if (m.contextWindow != null) '${compactTokens(m.contextWindow!)} ctx',
                      if (m.vision == true) 'vision',
                    ].join(' · '),
                    style: mono(context, size: 10.5, color: cs.onSurfaceVariant),
                  ),
                  trailing: m.providerId == providerId && m.name == modelName
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  onTap: () => Navigator.pop(context, m),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

/// Files the agent changed in this session, with "Undo changes".
Future<bool?> showCheckpointsSheet(BuildContext context, String desktopId, String sessionId) =>
    showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CheckpointsSheet(desktopId: desktopId, sessionId: sessionId),
    );

class _CheckpointsSheet extends ConsumerWidget {
  const _CheckpointsSheet({required this.desktopId, required this.sessionId});
  final String desktopId;
  final String sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final k = (desktopId: desktopId, sessionId: sessionId);
    final data = ref.watch(checkpointsProvider(k));
    final caps = ref.watch(capabilitiesProvider(desktopId));
    return _SheetFrame(
      title: 'Checkpoints',
      child: data.when(
        loading: () => const _SheetLoading(),
        error: (e, _) => ErrorPanel(
            message: e is RpcError ? e.readable : '$e',
            onRetry: () => ref.invalidate(checkpointsProvider(k))),
        data: (list) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              list.isEmpty
                  ? 'The agent has not changed any files in this session.'
                  : 'Files saved before the agent changed them. Undo puts them all back.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in list)
                ListTile(
                  dense: true,
                  leading: Icon(
                      c.isDir ? Icons.folder_outlined : (c.existed ? Icons.edit_note : Icons.add),
                      size: 18,
                      color: cs.onSurfaceVariant),
                  title: Text(c.relPath, style: mono(context, size: 12)),
                  subtitle: Text(
                    [c.existed ? 'changed' : 'created (undo deletes it)', relativeTime(c.createdAt)]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: mono(context, size: 10.5, color: cs.onSurfaceVariant),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: canRestoreCheckpoints(caps, list.length)
                  ? () => Navigator.pop(context, true)
                  : null,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Undo changes'),
            ),
          ),
          if (!caps.edit && list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(allowOnDesktopHint,
                  textAlign: TextAlign.center,
                  style: mono(context, size: 11, color: cs.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Eyebrow(title)),
              Flexible(child: child),
            ]),
          ),
        ),
      );
}

class _SheetLoading extends StatelessWidget {
  const _SheetLoading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}
