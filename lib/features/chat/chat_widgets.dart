import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/rpc/models.dart';
import '../../core/theme/app_theme.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.message});
  final Message message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SelectableText(message.content, style: const TextStyle(height: 1.4)),
        ),
      ),
    );
  }
}

class AssistantMessage extends StatelessWidget {
  const AssistantMessage({super.key, required this.message});
  final Message message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reasoning = message.reasoning?.trim() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (reasoning.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ReasoningBlock(text: reasoning, live: message.streaming && message.content.isEmpty),
        ),
      if (message.content.isNotEmpty) AssistantMarkdown(text: message.content),
      if (message.streaming && message.content.isEmpty && reasoning.isEmpty)
        Text('…', style: TextStyle(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Markdown for model output. Images and link navigation are blocked: the
/// text comes from a model and must not load or open anything.
class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final codeStyle = mono(context, size: 12.5, color: cs.onSurface);
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      imageBuilder: (uri, title, alt) => Text('[image${alt == null || alt.isEmpty ? '' : ': $alt'}]',
          style: TextStyle(color: cs.onSurfaceVariant)),
      onTapLink: (text, href, title) {
        if (href == null) return;
        Clipboard.setData(ClipboardData(text: href));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link copied')));
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: 14.5),
        code: codeStyle.copyWith(backgroundColor: cs.surfaceContainer),
        codeblockDecoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.outlineVariant),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.primary, width: 2)),
        ),
        a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
      ),
    );
  }
}

class ReasoningBlock extends StatefulWidget {
  const ReasoningBlock({super.key, required this.text, this.live = false});
  final String text;
  final bool live;
  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_open ? Icons.expand_more : Icons.chevron_right,
                size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Eyebrow(widget.live ? 'Reasoning…' : 'Reasoning'),
          ]),
        ),
      ),
      if (_open)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cs.outline))),
          child: SelectableText(widget.text,
              style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
        ),
    ]);
  }
}

String summarizeArgs(Map<String, dynamic> args) {
  for (final k in const ['command', 'path', 'file_path', 'url', 'pattern', 'query', 'description']) {
    final v = args[k];
    if (v is String && v.isNotEmpty) return v;
  }
  if (args.isEmpty) return '';
  return jsonEncode(args);
}

String clip(String s, int n) {
  final one = s.replaceAll('\n', ' ');
  return one.length > n ? '${one.substring(0, n)}…' : one;
}

({IconData icon, Color color, String label}) toolStatusLook(String status, ColorScheme cs) =>
    switch (status) {
      'success' => (icon: Icons.check, color: cs.primary, label: 'done'),
      'error' => (icon: Icons.close, color: cs.error, label: 'error'),
      'denied' => (icon: Icons.block, color: cs.error, label: 'denied'),
      'cancelled' => (icon: Icons.stop, color: cs.onSurfaceVariant, label: 'cancelled'),
      'awaiting_approval' => (icon: Icons.pan_tool_outlined, color: cs.secondary, label: 'needs approval'),
      'running' => (icon: Icons.more_horiz, color: cs.primary, label: 'running'),
      _ => (icon: Icons.schedule, color: cs.onSurfaceVariant, label: status),
    };

class ToolRunCard extends StatefulWidget {
  const ToolRunCard({
    super.key,
    required this.run,
    this.approval,
    this.deciding = false,
    required this.onDecide,
  });
  final ToolRun run;
  final Approval? approval;
  final bool deciding;
  final void Function(String approvalId, bool approved) onDecide;

  @override
  State<ToolRunCard> createState() => _ToolRunCardState();
}

class _ToolRunCardState extends State<ToolRunCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.run;
    final look = toolStatusLook(r.status, cs);
    final args = summarizeArgs(r.args);
    final result = r.error ?? r.resultSummary;
    final a = widget.approval;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: a != null && a.isPending ? cs.secondary : cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(look.icon, size: 14, color: look.color),
              const SizedBox(width: 8),
              Text(r.toolName, style: mono(context, size: 12, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(clip(args, 80),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 12, color: cs.onSurfaceVariant)),
              ),
              const SizedBox(width: 6),
              Text(look.label, style: mono(context, size: 10.5, color: look.color)),
            ]),
          ),
        ),
        if (_open) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Arguments'),
              const SizedBox(height: 4),
              MonoBox(text: const JsonEncoder.withIndent('  ').convert(r.args), maxHeight: 200),
              if (result != null && result.isNotEmpty) ...[
                const SizedBox(height: 10),
                Eyebrow(r.error != null ? 'Error' : 'Result'),
                const SizedBox(height: 4),
                MonoBox(text: result, maxHeight: 240),
              ],
            ]),
          ),
        ] else if (result != null && result.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 10, 8),
            child: Text(result,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: mono(context,
                    size: 11.5, color: r.error != null ? cs.error : cs.onSurfaceVariant)),
          ),
        if (a != null && a.isPending)
          ApprovalBody(approval: a, deciding: widget.deciding, onDecide: widget.onDecide),
      ]),
    );
  }
}

/// Standalone approval card (when its tool run is not known).
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.approval, required this.deciding, required this.onDecide});
  final Approval approval;
  final bool deciding;
  final void Function(String approvalId, bool approved) onDecide;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.secondary),
      ),
      child: ApprovalBody(approval: approval, deciding: deciding, onDecide: onDecide),
    );
  }
}

class ApprovalBody extends StatelessWidget {
  const ApprovalBody({super.key, required this.approval, required this.deciding, required this.onDecide});
  final Approval approval;
  final bool deciding;
  final void Function(String approvalId, bool approved) onDecide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = approval.preview;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Eyebrow('Approval · ${approval.kind}', color: cs.secondary),
        ]),
        const SizedBox(height: 6),
        Text(approval.description, style: const TextStyle(height: 1.4)),
        if (preview != null && preview.isNotEmpty) ...[
          const SizedBox(height: 8),
          MonoBox(text: preview, maxHeight: 260),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: deciding ? null : () => onDecide(approval.id, false),
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Deny'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: deciding ? null : () => onDecide(approval.id, true),
              child: deciding
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Approve'),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Applies once. No permanent grant.',
            style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Monospace, scrollable both ways (diffs, commands, JSON).
class MonoBox extends StatelessWidget {
  const MonoBox({super.key, required this.text, this.maxHeight = 220});
  final String text;
  final double maxHeight;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(text, style: mono(context, size: 11.5)),
        ),
      ),
    );
  }
}
