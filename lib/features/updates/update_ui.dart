import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/logo.dart';
import 'update_controller.dart';
import 'update_logic.dart';

String updateButtonLabel(UpdateState s) =>
    kDebugMode ? 'Install the release APK from GitHub' : 'Update to ${s.available?.version}';

/// "JenderalCode x.y.z is available" with the notes, Update / Later.
Future<void> showUpdateDialog(BuildContext context, WidgetRef ref, ReleaseInfo rel) async {
  final update = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('JenderalCode ${rel.version} is available'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.5),
        child: SingleChildScrollView(
          child: Text(rel.notes.isEmpty ? 'No release notes.' : rel.notes,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update')),
      ],
    ),
  );
  if (update == true) {
    if (context.mounted) context.push('/about');
    await ref.read(updateProvider.notifier).startUpdate();
  } else {
    ref.read(updateProvider.notifier).later(rel.version.toString());
  }
}

/// Small app-bar button while an update is pending.
class UpdateBadge extends ConsumerWidget {
  const UpdateBadge({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    if (s.available == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => context.push('/about'),
        icon: const Icon(Icons.system_update_alt, size: 16),
        label: Text('Update', style: mono(context, size: 11.5, weight: FontWeight.w600)),
      ),
    );
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(updateProvider);
    final ctl = ref.read(updateProvider.notifier);
    final rel = s.available;
    return Scaffold(
      appBar: AppBar(title: const Text('About / Updates')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Row(children: [Logo(size: 48), SizedBox(width: 14), Wordmark(fontSize: 22)]),
        const SizedBox(height: 20),
        const Eyebrow('Installed'),
        const SizedBox(height: 4),
        Text(s.installed ?? (updatesSupported ? '…' : 'unknown'), style: mono(context, size: 14)),
        if (kDebugMode)
          Text('debug build', style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        const Eyebrow('Updates'),
        const SizedBox(height: 8),
        if (!updatesSupported)
          Text('Updates are only available in the Android app.',
              style: TextStyle(color: cs.onSurfaceVariant))
        else ...[
          OutlinedButton.icon(
            onPressed: s.checking || s.busy ? null : () => ctl.check(manual: true),
            icon: s.checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Check for updates'),
          ),
          if (s.status != null) ...[
            const SizedBox(height: 8),
            Text(s.status!, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
          if (s.lastCheck != null)
            Text('Last checked ${TimeOfDay.fromDateTime(s.lastCheck!).format(context)}',
                style: mono(context, size: 11, color: cs.onSurfaceVariant)),
        ],
        if (rel != null) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('JenderalCode ${rel.version} is available',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(rel.notes.isEmpty ? 'No release notes.' : rel.notes,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
                const SizedBox(height: 14),
                _Action(s: s, ctl: ctl),
              ]),
            ),
          ),
        ],
        if (s.error != null) ...[
          const SizedBox(height: 12),
          Text(s.error!, style: TextStyle(color: cs.error)),
        ],
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.s, required this.ctl});
  final UpdateState s;
  final UpdateController ctl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (s.phase) {
      case UpdatePhase.downloading:
        final p = s.progress;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: p, minHeight: 4),
          const SizedBox(height: 6),
          Row(children: [
            Text(p == null ? 'Downloading…' : 'Downloading ${(p * 100).round()}%',
                style: mono(context, size: 12, color: cs.onSurfaceVariant)),
            const Spacer(),
            TextButton(onPressed: ctl.cancel, child: const Text('Cancel')),
          ]),
        ]);
      case UpdatePhase.verifying:
        return Text('Verifying SHA-256…', style: mono(context, size: 12));
      case UpdatePhase.installing:
        return Text('Waiting for the installer. Confirm the update on the system screen.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant));
      case UpdatePhase.needsPermission:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Android needs your permission for JenderalCode to install updates. '
            'Turn on "Allow from this source" for JenderalCode, then come back.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: ctl.openInstallSettings, child: const Text('Open settings')),
        ]);
      case UpdatePhase.idle:
      case UpdatePhase.failed:
        return FilledButton.icon(
          onPressed: ctl.startUpdate,
          icon: Icon(kDebugMode ? Icons.open_in_new : Icons.system_update_alt, size: 18),
          label: Text(s.phase == UpdatePhase.failed && !kDebugMode ? 'Try again' : updateButtonLabel(s)),
        );
    }
  }
}
