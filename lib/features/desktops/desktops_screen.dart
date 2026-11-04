import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/relay/relay_api.dart';
import '../../core/storage/secure_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/logo.dart';
import '../auth/auth_controller.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import '../updates/update_controller.dart';
import '../updates/update_ui.dart';
import 'desktops_controller.dart';

class DesktopsScreen extends ConsumerStatefulWidget {
  const DesktopsScreen({super.key});
  @override
  ConsumerState<DesktopsScreen> createState() => _DesktopsScreenState();
}

class _DesktopsScreenState extends ConsumerState<DesktopsScreen> {
  Map<String, Peer> _peers = const {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _sync(quiet: true));
    // An update found before this screen existed (e.g. during sign-in).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  void _maybePrompt() {
    if (!mounted) return;
    final s = ref.read(updateProvider);
    final rel = s.available;
    if (s.promptVersion == null || rel == null) return;
    ref.read(updateProvider.notifier).promptShown();
    showUpdateDialog(context, ref, rel);
  }

  Future<void> _sync({bool quiet = false}) async {
    try {
      await ref.read(desktopsProvider.future);
      final p = await ref.read(desktopsProvider.notifier).syncWithPeers();
      if (mounted) setState(() => _peers = p);
    } on RelayError catch (e) {
      if (e.isUnauthorized) {
        await ref.read(authProvider.notifier).signOutLocally(
            reason: 'This phone was signed out or revoked. Sign in again.');
      } else if (!quiet && mounted) {
        _snack(e.readable);
      }
    }
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _unpair(PairedDesktop d) async {
    final ok = await confirmDialog(context,
        title: 'Unpair ${d.name}?',
        body: 'This phone will no longer reach this desktop. You can pair again with a new QR code.',
        confirm: 'Unpair',
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(desktopsProvider.notifier).unpair(d.deviceId);
    } on RelayError catch (e) {
      if (mounted) _snack(e.readable);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context,
        title: 'Sign out?',
        body: 'This revokes this phone on the relay and forgets all paired desktops.',
        confirm: 'Sign out',
        destructive: true);
    if (ok) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final desktops = ref.watch(desktopsProvider);
    final presence = ref.watch(presenceProvider).value ?? const {};
    final account = ref.watch(authProvider).value?.account;
    ref.listen(updateProvider.select((s) => s.promptVersion), (_, v) {
      if (v != null) _maybePrompt();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Logo(size: 24),
          SizedBox(width: 10),
          Text('Desktops'),
        ]),
        actions: [
          const UpdateBadge(),
          const HelpButton(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'dark':
                  ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
                case 'light':
                  ref.read(themeModeProvider.notifier).set(ThemeMode.light);
                case 'system':
                  ref.read(themeModeProvider.notifier).set(ThemeMode.system);
                case 'about':
                  context.push('/about');
                case 'help':
                  openHelp(context);
                case 'logout':
                  _logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(account?.email ?? 'Signed in',
                    style: mono(context, size: 12, color: cs.onSurfaceVariant)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'dark', child: Text('Dark theme')),
              const PopupMenuItem(value: 'light', child: Text('Light theme')),
              const PopupMenuItem(value: 'system', child: Text('System theme')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'help', child: Text('Help · how to use')),
              const PopupMenuItem(value: 'about', child: Text('About / Updates')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      // The first-run guide has its own button.
      floatingActionButton: (desktops.value?.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/pair'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pair a desktop'),
            ),
      body: Column(children: [
        const ConnectionStrip(),
        Expanded(
          child: desktops.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => ErrorPanel(message: '$e', onRetry: _sync),
            data: (list) => RefreshIndicator(
              onRefresh: _sync,
              child: list.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
                      children: const [_Onboarding()],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final d = list[i];
                        final online = presence[d.deviceId] ?? _peers[d.deviceId]?.online ?? false;
                        final lastSeen = _peers[d.deviceId]?.lastSeen;
                        return _DesktopCard(
                          desktop: d,
                          online: online,
                          lastSeen: lastSeen,
                          onTap: () => context.push('/d/${d.deviceId}'),
                          onUnpair: () => _unpair(d),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// First run: how to pair, step by step.
class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(int n, IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Text('$n',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
              ]),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(child: Logo(size: 56)),
      const SizedBox(height: 16),
      Text('Connect your desktop',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 6),
      Text('Control JenderalCode Desktop from this phone in three steps.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Column(children: [
            step(1, Icons.desktop_windows_outlined, 'Open Remote control on the desktop',
                'Settings → Remote control → turn on "Allow remote control".'),
            step(2, Icons.qr_code_2, 'Show the QR code',
                'Press "Pair a phone". The desktop shows a QR code.'),
            step(3, Icons.qr_code_scanner, 'Scan it here',
                'Tap "Pair a desktop" below, scan, and check that both screens show the same 6-digit code.'),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => context.push('/pair'),
        icon: const Icon(Icons.qr_code_scanner, size: 18),
        label: const Text('Pair a desktop'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => openHelp(context, HelpTopic.start),
        icon: const Icon(Icons.help_outline, size: 18),
        label: const Text('Full guide'),
      ),
    ]);
  }
}

class _DesktopCard extends StatelessWidget {
  const _DesktopCard({
    required this.desktop,
    required this.online,
    required this.lastSeen,
    required this.onTap,
    required this.onUnpair,
  });
  final PairedDesktop desktop;
  final bool online;
  final int? lastSeen;
  final VoidCallback onTap;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = online
        ? 'online'
        : (lastSeen != null && lastSeen! > 0 ? 'offline · seen ${relativeTime(lastSeen!)}' : 'offline');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: online ? 0.14 : 0.06),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Icon(Icons.desktop_windows_outlined,
                    color: online ? cs.primary : cs.onSurfaceVariant),
              ),
              Positioned(right: -2, bottom: -2, child: OnlineDot(online: online, size: 11)),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(desktop.name,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${shortId(desktop.deviceId)} · $sub',
                    style: mono(context, size: 11.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
              onSelected: (_) => onUnpair(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'unpair', child: Text('Unpair')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
