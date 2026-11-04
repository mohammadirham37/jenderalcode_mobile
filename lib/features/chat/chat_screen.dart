import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/rpc/models.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import 'chat_catalog.dart';
import 'chat_controller.dart';
import 'chat_pickers.dart';
import 'chat_state.dart';
import 'chat_widgets.dart';
import 'composer.dart';
import 'composer_logic.dart';
import 'policy.dart';

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

const _yoloBlockedText =
    'This session uses Full access, which the desktop does not allow from the phone. '
    'Switch it to Balanced or Safe to control it, or $allowOnDesktopHint.';

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
  ChatKey get _key => (desktopId: widget.desktopId, sessionId: widget.sessionId);

  Future<bool> _send(String text, List<String> attachments, List<ImageAttachment> images) =>
      ref.read(chatProvider(_key).notifier).send(text, attachments: attachments, images: images);

  Future<void> _pickMode(ChatState s, Capabilities caps) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ModeSheet(current: s.session?.policyMode, caps: caps),
    );
    if (mode == null || !mounted) return;
    await ref.read(chatProvider(_key).notifier).setPolicy(
          mode: mode,
          caps: caps,
          confirmFullAccess: () => confirmDialog(
            context,
            title: fullAccessConfirmTitle,
            body: fullAccessConfirmText,
            confirm: 'Turn on Full access',
            destructive: true,
          ),
        );
  }

  Future<void> _pickAgent(ChatState s) async {
    final id = await showAgentSheet(context, widget.desktopId, s.session?.agentProfileId);
    if (id != null && mounted) await ref.read(chatProvider(_key).notifier).setAgent(id);
  }

  Future<void> _pickModel(ChatState s) async {
    final m = await showModelSheet(
        context, widget.desktopId, s.session?.providerId, s.session?.modelName);
    if (m == null || !mounted) return;
    if (m.providerId == s.session?.providerId && m.name == s.session?.modelName) return;
    await ref.read(chatProvider(_key).notifier).setModel(m.providerId, m.name);
  }

  Future<void> _checkpoints() async {
    final undo = await showCheckpointsSheet(context, widget.desktopId, widget.sessionId);
    if (undo != true || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Undo changes?',
      body: 'Every file the agent changed in this session goes back to how it was before, '
          'and files it created are deleted. Your own edits to those files since then are lost.',
      confirm: 'Undo changes',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final n = await ref.read(chatProvider(_key).notifier).restoreCheckpoints();
    ref.invalidate(checkpointsProvider((desktopId: widget.desktopId, sessionId: widget.sessionId)));
    if (n != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Restored $n file${n == 1 ? '' : 's'}.')));
    }
  }

  void _openProject(ChatState s, String tab) {
    final wid = s.session?.workspaceId;
    if (wid == null || wid.isEmpty) return;
    context.push('/d/${widget.desktopId}/w/$wid/p?tab=$tab');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(chatProvider(_key));
    final caps = ref.watch(capabilitiesProvider(widget.desktopId));
    final ctl = ref.read(chatProvider(_key).notifier);
    final online = ref.watch(presenceProvider).value?[widget.desktopId] ?? false;
    final title = s.session?.title ?? widget.initialTitle ?? 'Session';
    final items = buildTimeline(s).reversed.toList();
    final session = s.session;

    final agents = ref.watch(agentsProvider(widget.desktopId)).value;
    final catalog = ref.watch(modelsProvider(widget.desktopId)).value;
    final agent = agents?.where((a) => a.id == session?.agentProfileId).firstOrNull;
    final model = catalog?.find(session?.providerId, session?.modelName);
    final agentLabel = agent == null ? 'Agent' : '${agent.name} · ${agent.modeLabel}';
    final modelLabel = model?.label ?? session?.modelName ?? 'Model';
    final lastInput = s.usage?.lastInput ?? s.inputTokens;

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
                statusLabel(s.status, s.detail),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 11, color: s.busy ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
          ]),
        ]),
        actions: [
          if (session != null)
            ModeBadge(
              mode: session.policyMode,
              busy: s.settingPolicy,
              onTap: () => _pickMode(s, caps),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => switch (v) {
              'checkpoints' => _checkpoints(),
              _ => _openProject(s, v),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'checkpoints', child: Text('Checkpoints · undo changes')),
              if (session != null) ...const [
                PopupMenuItem(value: 'changes', child: Text('Changes')),
                PopupMenuItem(value: 'files', child: Text('Files')),
                PopupMenuItem(value: 'git', child: Text('Git')),
                PopupMenuItem(value: 'terminal', child: Text('Terminal')),
              ],
            ],
          ),
        ],
        bottom: s.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Column(children: [
        const ConnectionStrip(),
        if (session?.isYolo == true && !caps.fullAccess)
          _Banner(text: _yoloBlockedText, color: cs.error),
        Expanded(
          child: s.loading && session == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : s.loadError != null && session == null
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
        Composer(
          desktopId: widget.desktopId,
          workspaceId: session?.workspaceId,
          busy: s.busy,
          sending: s.sending,
          imagesAllowed: imagesAllowedFor(model),
          onSend: _send,
          onStop: ctl.cancel,
          toolbar: session == null
              ? null
              : ChatToolbar(
                  agentLabel: agentLabel,
                  modelLabel: modelLabel,
                  onAgent: s.updatingSession ? null : () => _pickAgent(s),
                  onModel: s.updatingSession ? null : () => _pickModel(s),
                  busy: s.updatingSession,
                  lastInput: lastInput,
                  contextWindow: model?.contextWindow,
                ),
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

/// Header control showing the session's permission mode. In Full access it
/// turns red with a crossed-out shield, like the desktop's ShieldOff badge.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.mode, required this.onTap, this.busy = false});
  final String? mode;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final yolo = mode == 'yolo';
    final color = yolo ? cs.error : cs.onSurfaceVariant;
    return Tooltip(
      message: 'Permission mode',
      child: Material(
        color: yolo ? cs.error.withValues(alpha: 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: yolo ? cs.error.withValues(alpha: 0.6) : cs.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5))
              else
                Icon(yolo ? Icons.remove_moderator_outlined : Icons.shield_outlined,
                    size: 14, color: color),
              const SizedBox(width: 5),
              Text(policyLabel(mode).toUpperCase(),
                  style: mono(context, size: 10.5, color: color, weight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.current, required this.caps});
  final String? current;
  final Capabilities caps;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Permission mode'),
          const SizedBox(height: 4),
          Text('Currently: ${policyLabel(current)}',
              style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final m in policyModes) _option(context, m),
        ]),
      ),
    );
  }

  Widget _option(BuildContext context, String m) {
    final cs = Theme.of(context).colorScheme;
    final allowed = policyModeAllowed(m, caps);
    final selected = m == current;
    final yolo = m == 'yolo';
    final accent = yolo ? cs.error : cs.primary;
    return ListTile(
      enabled: allowed,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        yolo ? Icons.remove_moderator_outlined : (m == 'safe' ? Icons.verified_user_outlined : Icons.shield_outlined),
        color: allowed ? (yolo ? cs.error : cs.onSurfaceVariant) : null,
      ),
      title: Text(policyLabel(m),
          style: TextStyle(color: allowed && yolo ? cs.error : null, fontWeight: FontWeight.w600)),
      subtitle: Text(allowed ? policyDescription(m) : allowOnDesktopHint),
      trailing: selected ? Icon(Icons.check, color: accent) : null,
      onTap: allowed && !selected ? () => Navigator.pop(context, m) : null,
    );
  }
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
