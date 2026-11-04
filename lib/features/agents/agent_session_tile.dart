import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/models.dart';
import '../../core/theme/app_theme.dart';
import 'agent_cli.dart';

/// An agent CLI terminal (`kind:"agent"`) in a session list. Bypass tabs
/// opened from this phone get the red ShieldOff mark.
class AgentSessionTile extends ConsumerWidget {
  const AgentSessionTile({super.key, required this.t, required this.onTap, this.onClose});
  final RemoteTerminal t;
  final VoidCallback onTap;

  /// Only for phone-opened terminals (`terminal.close` is `origin:"remote"` only).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final bypass = t.bypass || ref.watch(bypassTerminalsProvider).contains(t.id);
    final meta = [
      'agent CLI',
      t.isRemote ? 'opened from phone · also on desktop' : 'desktop tab',
      '${t.cols}×${t.rows}',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 14, onClose == null ? 14 : 4, 14),
          child: Row(children: [
            Icon(bypass ? Icons.remove_moderator_outlined : Icons.smart_toy_outlined,
                size: 20, color: bypass ? cs.error : cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title.isEmpty ? 'Agent' : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(bypass ? '$meta · bypass' : meta,
                    style: mono(context, size: 11.5, color: bypass ? cs.error : cs.onSurfaceVariant)),
              ]),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                onPressed: onClose,
              ),
          ]),
        ),
      ),
    );
  }
}
