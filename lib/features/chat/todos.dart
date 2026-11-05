import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/theme/app_theme.dart';
import 'chat_controller.dart';

/// One item of the agent's checklist (`todo_write` arguments).
class TodoItem {
  const TodoItem(this.content, this.status);
  final String content;

  /// pending | in_progress | completed
  final String status;

  bool get done => status == 'completed';
  bool get active => status == 'in_progress';
}

/// The agent's current checklist: the newest successful `todo_write` run,
/// like the desktop's todo dock. Null when the agent has not written one.
List<TodoItem>? latestTodos(Iterable<ToolRun> runs) {
  ToolRun? best;
  for (final r in runs) {
    if (r.toolName == 'todo_write' && r.status == 'success' && (best == null || r.createdAt >= best.createdAt)) {
      best = r;
    }
  }
  final raw = best?.args['todos'];
  if (raw is! List) return null;
  final items = [
    for (final t in raw)
      if (t is Map && t['content'] is String && (t['content'] as String).trim().isNotEmpty)
        TodoItem((t['content'] as String).trim(), t['status'] is String ? t['status'] as String : 'pending'),
  ];
  return items.isEmpty ? null : items;
}

/// Header button with the progress ("2/5"); opens [showTodosSheet]. Hidden
/// until the agent writes a checklist.
class TodosButton extends ConsumerWidget {
  const TodosButton({super.key, required this.chatKey});
  final ChatKey chatKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(chatProvider(chatKey).select((s) => latestTodos(s.toolRuns.values)));
    if (todos == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final done = todos.where((t) => t.done).length;
    final all = done == todos.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: all ? cs.onSurfaceVariant : cs.primary,
        ),
        onPressed: () => showTodosSheet(context, chatKey),
        icon: Icon(all ? Icons.checklist : Icons.checklist_rtl, size: 18),
        label: Text('$done/${todos.length}', style: mono(context, size: 12, weight: FontWeight.w600)),
      ),
    );
  }
}

/// The checklist in a bottom sheet that follows the agent live.
Future<void> showTodosSheet(BuildContext context, ChatKey chatKey) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TodosSheet(chatKey: chatKey),
    );

class _TodosSheet extends ConsumerWidget {
  const _TodosSheet({required this.chatKey});
  final ChatKey chatKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final todos = ref.watch(chatProvider(chatKey).select((s) => latestTodos(s.toolRuns.values))) ?? const [];
    final busy = ref.watch(chatProvider(chatKey).select((s) => s.busy));
    final done = todos.where((t) => t.done).length;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.checklist_rtl, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text('Todos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$done/${todos.length}', style: mono(context, size: 12.5, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: todos.isEmpty ? 0 : done / todos.length,
                backgroundColor: cs.surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              todos.isEmpty
                  ? 'The agent has no checklist yet.'
                  : done == todos.length
                      ? 'All done.'
                      : busy
                          ? 'Updates live while the agent works.'
                          : 'The agent\'s plan for this task.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: todos.length,
                itemBuilder: (_, i) => _TodoRow(item: todos[i]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.item});
  final TodoItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = item.done
        ? Icon(Icons.check_circle, size: 20, color: cs.primary)
        : item.active
            ? Icon(Icons.play_circle_outline, size: 20, color: cs.primary)
            : Icon(Icons.radio_button_unchecked, size: 20, color: cs.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: item.active ? cs.primary.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(radius),
        border: item.active ? Border.all(color: cs.primary.withValues(alpha: 0.35)) : null,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.content,
            style: TextStyle(
              height: 1.4,
              fontWeight: item.active ? FontWeight.w600 : FontWeight.w400,
              color: item.done ? cs.onSurfaceVariant : cs.onSurface,
              decoration: item.done ? TextDecoration.lineThrough : null,
              decorationColor: cs.onSurfaceVariant,
            ),
          ),
        ),
      ]),
    );
  }
}
