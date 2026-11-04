import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/relay/relay_api.dart';
import '../../core/storage/secure_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desktops'),
        actions: [
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
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      EmptyPanel(
                        title: 'No desktops yet',
                        body:
                            'On the desktop, turn on Remote and show the pairing QR code. Then tap "Pair a desktop".',
                      ),
                    ])
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
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(children: [
            OnlineDot(online: online),
            const SizedBox(width: 12),
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
