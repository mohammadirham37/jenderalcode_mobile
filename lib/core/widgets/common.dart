import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../relay/relay_socket.dart';
import '../theme/app_theme.dart';

class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, required this.online, this.size = 8});
  final bool online;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? Accent.a400 : Colors.transparent,
        border: Border.all(
            color: online ? Accent.a400 : cs.onSurfaceVariant, width: 1.2),
      ),
    );
  }
}

/// Thin strip under the app bar while the relay link is down.
class ConnectionStrip extends ConsumerWidget {
  const ConnectionStrip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(socketStateProvider).value;
    final cs = Theme.of(context).colorScheme;
    final String? text = switch (s) {
      SocketState.connecting => 'Connecting to relay…',
      SocketState.disconnected => 'Relay offline. Retrying…',
      SocketState.replaced => 'Connected from another place. Tap to reconnect.',
      SocketState.stopped => 'Disconnected.',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Material(
      color: cs.surfaceContainer,
      child: InkWell(
        onTap: () => ref.read(hubProvider)?.socket.resume(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant))),
          child: Row(children: [
            if (s == SocketState.connecting)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                    width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              ),
            Expanded(
              child: Text(text,
                  style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.title, this.body, this.action});
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Eyebrow(title),
          if (body != null) ...[
            const SizedBox(height: 10),
            Text(body!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String relativeTime(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

Future<bool> confirmDialog(BuildContext context,
    {required String title,
    required String body,
    required String confirm,
    bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error)
              : null,
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == true;
}
