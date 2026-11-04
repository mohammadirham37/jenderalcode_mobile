import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../desktops/capabilities.dart';
import 'agent_cli.dart';

/// What the user picked in the "New session" sheet.
sealed class NewSessionChoice {
  const NewSessionChoice();
}

class NewChatChoice extends NewSessionChoice {
  const NewChatChoice();
}

class NewAgentChoice extends NewSessionChoice {
  const NewAgentChoice(this.cli, {required this.resume, required this.bypass});
  final AgentCliInfo cli;
  final bool resume;
  final bool bypass;
}

/// Like the desktop's "+" menu: JenderalCode chat or an agent CLI.
Future<NewSessionChoice?> showNewSessionSheet(BuildContext context, String desktopId) =>
    showModalBottomSheet<NewSessionChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NewSessionSheet(desktopId: desktopId),
    );

class _NewSessionSheet extends ConsumerStatefulWidget {
  const _NewSessionSheet({required this.desktopId});
  final String desktopId;
  @override
  ConsumerState<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends ConsumerState<_NewSessionSheet> {
  AgentCliInfo? _picked;
  bool _resume = false;
  bool _bypass = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caps = ref.watch(capabilitiesProvider(widget.desktopId));
    final clis = ref.watch(agentClisProvider(widget.desktopId));
    final picked = _picked;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: picked != null ? _options(context, picked) : ListView(shrinkWrap: true, children: [
            const Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 8), child: Eyebrow('New session')),
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: cs.primary),
              title: const Text('JenderalCode chat', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('The desktop agent, with approvals on this phone'),
              onTap: () => Navigator.pop(context, const NewChatChoice()),
            ),
            const Divider(),
            const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 4), child: Eyebrow('Agent CLI')),
            if (!caps.terminal)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(allowOnDesktopHint, style: mono(context, size: 11, color: cs.onSurfaceVariant)),
              ),
            ...clis.when(
              loading: () => const [
                Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ],
              error: (e, _) => [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(e is RpcError ? e.readable : '$e', style: TextStyle(color: cs.error)),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No agent CLIs are enabled on the desktop.',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    ]
                  : [for (final c in list) _cliTile(context, c, caps.terminal)],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cliTile(BuildContext context, AgentCliInfo c, bool enabled) {
    final cs = Theme.of(context).colorScheme;
    final dim = !c.installed;
    return Opacity(
      opacity: dim && enabled ? 0.55 : 1,
      child: ListTile(
        enabled: enabled,
        leading: const Icon(Icons.smart_toy_outlined),
        title: Row(children: [
          Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (dim) ...[
            const SizedBox(width: 8),
            Text('not installed', style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
          ],
        ]),
        subtitle: Text(c.command,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 11.5)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() {
          _picked = c;
          _resume = false;
          _bypass = false;
        }),
      ),
    );
  }

  Widget _options(BuildContext context, AgentCliInfo c) {
    final cs = Theme.of(context).colorScheme;
    final o = launchOptionsFor(c);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _picked = null),
        ),
        Expanded(child: Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(c.command, style: mono(context, size: 12, color: cs.onSurfaceVariant)),
      ),
      if (!c.installed)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Not found on the desktop\'s PATH. It may fail to start.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
      if (o.resume)
        SwitchListTile(
          title: const Text('Continue last conversation'),
          value: _resume,
          onChanged: (v) => setState(() => _resume = v),
        ),
      if (o.bypass)
        SwitchListTile(
          secondary: Icon(Icons.remove_moderator_outlined, color: cs.error),
          title: Text('Bypass permissions', style: TextStyle(color: cs.error)),
          subtitle: const Text('Runs commands and edits files without asking'),
          value: _bypass,
          activeThumbColor: cs.error,
          onChanged: (v) => setState(() => _bypass = v),
        ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          onPressed: () =>
              Navigator.pop(context, NewAgentChoice(c, resume: _resume, bypass: _bypass)),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text('Start ${c.name}'),
        ),
      ),
    ]);
  }
}
