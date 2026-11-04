import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'chat_controller.dart';
import 'chat_state.dart';
import 'chat_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.desktopId,
    required this.sessionId,
    this.initialTitle,
  });
  final String desktopId;
  final String sessionId;
  final String? initialTitle;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

const _yoloText =
    'This session uses Full access. Change its mode on the desktop to control it remotely.';

String statusLabel(String status, String? detail) {
  final base = switch (status) {
    'idle' => 'idle',
    'thinking' => 'thinking',
    'streaming' => 'writing',
    'running_tool' => 'running tool',
    'waiting_approval' => 'waiting for approval',
    _ => status,
  };
  return detail != null && detail.isNotEmpty ? '$base · $detail' : base;
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();

  ChatKey get _key => (desktopId: widget.desktopId, sessionId: widget.sessionId);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final ok = await ref.read(chatProvider(_key).notifier).send(text);
    if (ok && mounted && _input.text == text) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(chatProvider(_key));
    final ctl = ref.read(chatProvider(_key).notifier);
    final online = ref.watch(presenceProvider).value?[widget.desktopId] ?? false;
    final title = s.session?.title ?? widget.initialTitle ?? 'Session';
    final items = buildTimeline(s).reversed.toList();
    final tokens = s.inputTokens != null ? ' · ${s.inputTokens} in / ${s.outputTokens ?? 0} out' : '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.isEmpty ? 'Untitled session' : title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 2),
          Row(children: [
            OnlineDot(online: online, size: 6),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${statusLabel(s.status, s.detail)}$tokens',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 11, color: s.busy ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
          ]),
        ]),
        bottom: s.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Column(children: [
        const ConnectionStrip(),
        if (s.session?.isYolo == true)
          _Banner(text: _yoloText, color: cs.error),
        Expanded(
          child: s.loading && s.session == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : s.loadError != null && s.session == null
                  ? ErrorPanel(message: s.loadError!, onRetry: ctl.reload)
                  : items.isEmpty
                      ? const EmptyPanel(title: 'Empty session', body: 'Send a message to start.')
                      : ListView.separated(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _item(items[i], s, ctl),
                        ),
        ),
        if (s.lastError != null)
          _Banner(text: s.lastError!, color: cs.error, onClose: ctl.clearError),
        _Composer(
          controller: _input,
          busy: s.busy,
          sending: s.sending,
          onSend: _send,
          onStop: ctl.cancel,
        ),
      ]),
    );
  }

  Widget _item(TimelineItem it, ChatState s, ChatController ctl) => switch (it) {
        MessageItem(:final message) => message.role == 'user'
            ? UserBubble(message: message)
            : AssistantMessage(message: message),
        ToolRunItem(:final run, :final approval) => ToolRunCard(
            run: run,
            approval: approval,
            deciding: approval != null && s.deciding.contains(approval.id),
            onDecide: ctl.decide,
          ),
        ApprovalItem(:final approval) => ApprovalCard(
            approval: approval,
            deciding: s.deciding.contains(approval.id),
            onDecide: ctl.decide,
          ),
      };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, this.onClose});
  final String text;
  final Color color;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(color: color.withValues(alpha: 0.4)),
            bottom: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
          if (onClose != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: color),
              onPressed: onClose,
            ),
        ]),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.sending,
    required this.onSend,
    required this.onStop,
  });
  final TextEditingController controller;
  final bool busy;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: busy ? 'Steer the running turn…' : 'Message the agent…',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (busy) ...[
            IconButton.outlined(
              tooltip: 'Stop',
              onPressed: onStop,
              icon: Icon(Icons.stop, color: cs.error),
            ),
            const SizedBox(width: 6),
          ],
          IconButton.filled(
            tooltip: busy ? 'Steer' : 'Send',
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_upward),
          ),
        ]),
      ),
    );
  }
}
