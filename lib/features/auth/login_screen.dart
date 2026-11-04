import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/logo.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(authNoticeProvider.notifier).show(null);
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = e is AuthFailure ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notice = ref.watch(authNoticeProvider);
    final auth = ref.read(authProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: Logo(size: 72)),
                  const SizedBox(height: 24),
                  const Eyebrow('Remote · v1'),
                  const SizedBox(height: 8),
                  Text('JenderalCode',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: cs.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    'Chat with your desktop agent, approve its actions and stop turns from your phone. '
                    'Messages are end-to-end encrypted; the relay only forwards ciphertext.',
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                  const SizedBox(height: 32),
                  if (notice != null) ...[
                    _Note(text: notice, color: cs.secondary),
                    const SizedBox(height: 16),
                  ],
                  if (AppConfig.devLogin) ...[
                    const Eyebrow('Dev login'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'you@example.com'),
                      onSubmitted: (_) => _run(() => auth.loginDev(_email.text)),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(() => auth.loginDev(_email.text)),
                      child: const Text('Sign in'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run(auth.loginGoogle),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Sign in with Google'),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _Note(text: _error!, color: cs.error),
                  ],
                  const SizedBox(height: 32),
                  const Eyebrow('Relay'),
                  const SizedBox(height: 4),
                  Text(
                    AppConfig.hasRelay ? AppConfig.relayBase : 'not configured (RELAY_URL)',
                    style: mono(context, size: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(color: color)),
      );
}
