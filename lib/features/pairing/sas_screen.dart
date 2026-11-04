import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/crypto/sas.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../desktops/desktops_controller.dart';
import 'pairing_service.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';

/// Step 2: compare the code with the desktop, then Connect.
class SasScreen extends ConsumerStatefulWidget {
  const SasScreen({super.key, required this.pending});
  final PendingPairing pending;
  @override
  ConsumerState<SasScreen> createState() => _SasScreenState();
}

class _SasScreenState extends ConsumerState<SasScreen> {
  Timer? _tick;
  bool _working = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    final session = ref.read(authProvider).value;
    if (session == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final d = await PairingService(ref.read(relayApiProvider), session.keys)
          .approve(widget.pending);
      await ref.read(desktopsProvider.notifier).add(d);
      if (mounted) setState(() => _done = true);
    } on PairingFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.pending;
    final left = ((p.claim.expiresAt - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final expired = left <= 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify desktop'),
        actions: const [HelpButton(topic: HelpTopic.start)],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Eyebrow(_done ? 'Paired' : 'Step 2 of 2'),
          const SizedBox(height: 6),
          Text(p.qr.desktopName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (p.claim.desktopName.isNotEmpty && p.claim.desktopName != p.qr.desktopName)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Relay calls it "${p.claim.desktopName}"',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: cs.outline),
            ),
            child: Column(children: [
              const Eyebrow('Verification code'),
              const SizedBox(height: 12),
              Text(formatSas(p.sas),
                  style: mono(context, size: 40, weight: FontWeight.w600, color: cs.primary)
                      .copyWith(letterSpacing: 4)),
            ]),
          ),
          const SizedBox(height: 20),
          if (_done) ...[
            const Text(
                'This phone is paired. Now confirm the same code on the desktop. Until you do, the desktop ignores this phone.'),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Done')),
          ] else ...[
            const Text(
                'Check that the desktop shows exactly this code. Only tap Connect if it matches.'),
            const SizedBox(height: 8),
            Text(expired ? 'Code expired' : 'Expires in ${left}s',
                style: mono(context, size: 12, color: expired ? cs.error : cs.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _working || expired ? null : _connect,
                  child: _working
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
