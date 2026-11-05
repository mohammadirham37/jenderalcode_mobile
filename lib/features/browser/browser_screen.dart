import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/providers.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import 'browser_proxy.dart';

/// The phone browser (§6.10): shows a dev server running on the desktop
/// (`localhost:<port>`) through [BrowserProxy].
class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key, required this.desktopId, this.initialUrl});
  final String desktopId;
  final String? initialUrl;

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  late final BrowserProxy _proxy = BrowserProxy(_rpc);
  late final WebViewController _web;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  List<String> _targets = const [];
  bool _started = false;
  int _progress = 100;
  bool _canBack = false;
  bool _canForward = false;
  String? _error;

  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic> params) {
    final hub = ref.read(hubProvider);
    if (hub == null || !hub.isKnown(widget.desktopId)) throw const RpcError('offline');
    return hub.rpc(widget.desktopId).call(method, params);
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onUrlChange: (c) => _showUrl(c.url),
        onPageFinished: (_) => _updateHistory(),
        onNavigationRequest: _onNavigation,
      ));
    _address.text = widget.initialUrl ?? '';
    Future.microtask(_loadTargets);
    if (widget.initialUrl != null) Future.microtask(() => _go(widget.initialUrl!));
  }

  @override
  void dispose() {
    _proxy.stop();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final r = await _rpc('browser.targets', {});
      final list = [for (final t in (r['targets'] as List? ?? const [])) if (t is Map && t['url'] is String) t['url'] as String];
      if (!mounted) return;
      setState(() => _targets = list);
      if (!_started && _address.text.isEmpty && list.isNotEmpty) _address.text = list.first;
    } on RpcError {
      // Older desktop or not allowed: the address bar still works.
    }
  }

  void _showUrl(String? local) {
    final u = local == null ? null : Uri.tryParse(local);
    final t = u == null ? null : _proxy.toTarget(u);
    if (t != null && !_addressFocus.hasFocus) _address.text = t.toString();
    _updateHistory();
  }

  Future<void> _updateHistory() async {
    final back = await _web.canGoBack();
    final fwd = await _web.canGoForward();
    if (mounted) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  /// Opens [input] (`5173`, `localhost:5173/app`, a full URL).
  Future<void> _go(String input) async {
    final target = parseBrowserAddress(input);
    if (target == null) {
      setState(() => _error = 'Enter an address on the desktop, like localhost:5173 or 127.0.0.1:8000.');
      return;
    }
    _addressFocus.unfocus();
    setState(() => _error = null);
    try {
      await _proxy.start(target);
      final local = _proxy.toLocal(target)!;
      _address.text = target.toString();
      setState(() => _started = true);
      await _web.loadRequest(local);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the browser: $e');
    }
  }

  Future<NavigationDecision> _onNavigation(NavigationRequest r) async {
    final u = Uri.tryParse(r.url);
    if (u == null) return NavigationDecision.prevent;
    // Our proxy, or a page the proxy serves through its port.
    final base = _proxy.base;
    if (base != null && u.host == base.host && u.port == base.port) return NavigationDecision.navigate;
    if (u.scheme == 'about' || u.scheme == 'data' || u.scheme == 'blob') return NavigationDecision.navigate;
    // Another dev server on the desktop: switch to it.
    if (parseBrowserAddress(r.url) != null || (u.host == '127.0.0.1' && u.hasPort)) {
      final target = u.host == '127.0.0.1' ? u.replace(host: 'localhost') : u;
      Future.microtask(() => _go(target.toString()));
      return NavigationDecision.prevent;
    }
    // Anything else (the internet) opens in the phone's own browser.
    if (u.scheme == 'http' || u.scheme == 'https') {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allowed = ref.watch(capabilitiesProvider(widget.desktopId)).browser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browser'),
        actions: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: _canBack ? () => _web.goBack() : null,
          ),
          IconButton(
            tooltip: 'Forward',
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: _canForward ? () => _web.goForward() : null,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _started ? () => _web.reload() : null,
          ),
          const HelpButton(topic: HelpTopic.browser),
        ],
        bottom: _started && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2, value: _progress / 100))
            : null,
      ),
      body: Column(children: [
        const ConnectionStrip(),
        if (!allowed)
          Expanded(
            child: EmptyPanel(
              title: 'Browser is off',
              body: 'The phone browser shows dev servers running on the desktop. $allowOnDesktopHint '
                  '(Allow Full access & terminal from phone).',
              action: TextButton.icon(
                onPressed: () => openHelp(context, HelpTopic.browser),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('How it works'),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: TextField(
              controller: _address,
              focusNode: _addressFocus,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              style: mono(context, size: 13),
              decoration: InputDecoration(
                hintText: 'localhost:5173',
                prefixIcon: const Icon(Icons.desktop_windows_outlined, size: 18),
                suffixIcon: IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _go(_address.text),
                ),
              ),
              onSubmitted: _go,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
            ),
          Expanded(
            child: _started
                ? WebViewWidget(controller: _web)
                : _Start(targets: _targets, onPick: (u) => _go(u)),
          ),
        ],
      ]),
    );
  }
}

/// Before a page is open: what this is, and the desktop's open previews.
class _Start extends StatelessWidget {
  const _Start({required this.targets, required this.onPick});
  final List<String> targets;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('Open a dev server running on the desktop, for example localhost:5173 (Vite), '
          'localhost:3000 (Next.js) or 127.0.0.1:8000 (Laravel, Django).',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)),
      const SizedBox(height: 6),
      Text('Pages load through the desktop, so the computer must be online. '
          'Live reload (HMR) does not work yet: tap Reload after changes.',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.45, fontSize: 12.5)),
      if (targets.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Eyebrow('Open on the desktop'),
        const SizedBox(height: 8),
        for (final t in targets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(Icons.public, color: cs.primary),
                title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 13)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onPick(t),
              ),
            ),
          ),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in const ['localhost:5173', 'localhost:3000', '127.0.0.1:8000', 'localhost:8080'])
          ActionChip(label: Text(p, style: mono(context, size: 12.5)), onPressed: () => onPick(p)),
      ]),
    ]);
  }
}
