import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'pairing_service.dart';
import 'qr_payload.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (_working) return;
    for (final b in c.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handle(raw);
        return;
      }
    }
  }

  Future<void> _handle(String raw) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final qr = parsePairingQr(raw, relayUrl: AppConfig.relayBase);
      final session = ref.read(authProvider).value;
      if (session == null) throw const PairingFailure('Not signed in.');
      await _controller.stop();
      final pending =
          await PairingService(ref.read(relayApiProvider), session.keys).claim(qr);
      if (!mounted) return;
      await context.push('/pair/confirm', extra: pending);
      // Back from "Cancel": scan again.
      if (mounted) {
        setState(() => _working = false);
        _controller.start().ignore();
      }
    } on QrParseError catch (e) {
      _fail(e.message);
    } on PairingFailure catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = msg;
    });
    _controller.start().ignore();
  }

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enter pairing link'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: mono(c),
          decoration: const InputDecoration(hintText: 'jcode://pair?v=1&c=…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Continue')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null && v.trim().isNotEmpty) _handle(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a desktop'),
        actions: [
          const HelpButton(topic: HelpTopic.start),
          IconButton(
            tooltip: 'Enter link',
            icon: const Icon(Icons.keyboard),
            onPressed: _working ? null : _paste,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(error: error, onRetry: () {
                _controller.start().ignore();
              }),
            ),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Accent.a400, width: 1.5),
                ),
              ),
            ),
            if (_working)
              Container(
                color: Neutral.n950.withValues(alpha: 0.6),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Step 1 of 2'),
            const SizedBox(height: 6),
            const Text('Scan the QR code shown on the desktop.'),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});
  final MobileScannerException error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined),
          const SizedBox(height: 12),
          Text(
            denied
                ? 'Camera permission is needed to scan the pairing code. Allow it in Android settings, or enter the link with the keyboard button.'
                : 'The camera could not start (${error.errorCode.name}).',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}
