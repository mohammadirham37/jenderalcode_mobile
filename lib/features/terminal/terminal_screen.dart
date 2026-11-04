import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../agents/agent_cli.dart';
import 'extra_keys.dart';
import 'terminal_controller.dart';
import 'terminal_look.dart';
import 'terminal_state.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    super.key,
    required this.desktopId,
    required this.terminalId,
    this.initialTitle,
  });
  final String desktopId;
  final String terminalId;
  final String? initialTitle;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late final AppLifecycleListener _lifecycle;
  final _focus = FocusNode();
  final _hScroll = ScrollController();
  double _fontSize = defaultTerminalFontSize;

  // Pinch zoom, tracked from raw pointers so scrolling keeps working.
  final _pointers = <int, Offset>{};
  double? _pinchStartDistance;
  double _pinchStartFont = defaultTerminalFontSize;

  TermKey get _key => (desktopId: widget.desktopId, terminalId: widget.terminalId);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(terminalSessionProvider(_key).notifier).reattach(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _focus.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _zoom(double size) {
    final s = size.clamp(minTerminalFontSize, maxTerminalFontSize).toDouble();
    if ((s - _fontSize).abs() < 0.25) return;
    setState(() => _fontSize = s);
  }

  double? _distance() {
    if (_pointers.length < 2) return null;
    final p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _distance();
      _pinchStartFont = _fontSize;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStartDistance;
    final now = _distance();
    if (start != null && now != null && start > 20) _zoom(_pinchStartFont * now / start);
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    ref.read(terminalSessionProvider(_key).notifier).paste(text);
  }

  Future<void> _close() async {
    final ok = await confirmDialog(
      context,
      title: 'Close terminal?',
      body: 'This ends the shell and every process running in it.',
      confirm: 'Close',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final closed = await ref.read(terminalSessionProvider(_key).notifier).close();
    if (closed && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(terminalSessionProvider(_key));
    final ctl = ref.read(terminalSessionProvider(_key).notifier);
    final info = s.info;
    final remote = info?.isRemote ?? false;
    final bypass = (info?.bypass ?? false) || ref.watch(bypassTerminalsProvider).contains(widget.terminalId);
    final title = (info?.title.isNotEmpty ?? false) ? info!.title : (widget.initialTitle ?? 'Terminal');
    final meta = [
      if (info != null) info.isAgent ? 'agent' : 'shell',
      if (info != null) remote ? 'phone' : 'desktop tab',
      '${s.cols}×${s.rows}',
      if (s.attaching) 'attaching…',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (bypass) ...[
              Icon(Icons.remove_moderator_outlined, size: 16, color: cs.error),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 2),
          Text(meta, style: mono(context, size: 11, color: cs.onSurfaceVariant)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease, size: 20),
            onPressed: () => _zoom(_fontSize - 1),
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase, size: 20),
            onPressed: () => _zoom(_fontSize + 1),
          ),
          if (remote)
            IconButton(
              tooltip: 'Close terminal',
              icon: Icon(Icons.close, color: cs.error),
              onPressed: _close,
            ),
        ],
        bottom: s.attaching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Column(children: [
        const ConnectionStrip(),
        if (s.exited)
          _Strip(
            text: s.exitCode == null ? processExitedText : '$processExitedText · code ${s.exitCode}',
            color: cs.onSurfaceVariant,
          ),
        if (s.error != null) _Strip(text: s.error!, color: cs.error, onClose: ctl.clearError),
        Expanded(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: _terminal(context, s, ctl, remote),
          ),
        ),
        _ExtraKeyBar(
          ctrlArmed: s.ctrlArmed,
          enabled: !s.exited,
          onKey: (k) {
            ctl.pressKey(k);
            if (!_focus.hasFocus) _focus.requestFocus();
          },
          onPaste: _paste,
        ),
      ]),
    );
  }

  Widget _terminal(BuildContext context, TermState s, TerminalSessionController ctl, bool remote) {
    final theme = terminalThemeFor(Theme.of(context).brightness);
    final style = terminalStyle(_fontSize);
    Widget view({required bool autoResize}) => TerminalView(
          ctl.emulator,
          key: ValueKey(s.generation),
          focusNode: _focus,
          autofocus: true,
          autoResize: autoResize,
          theme: theme,
          textStyle: style,
          textScaler: TextScaler.noScaling,
          padding: const EdgeInsets.all(terminalPadding),
          readOnly: s.exited,
          keyboardAppearance: Theme.of(context).brightness,
          deleteDetection: true,
        );
    if (remote || s.info == null) {
      return ColoredBox(color: theme.background, child: view(autoResize: true));
    }
    // Desktop tab: render at the desktop's grid and scroll sideways; never
    // resize it from here.
    final cell = measureCell(style);
    final width = s.cols * cell.width + terminalPadding * 2 + 1;
    return ColoredBox(
      color: theme.background,
      child: LayoutBuilder(
        builder: (_, c) => Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width < c.maxWidth ? c.maxWidth : width,
              height: c.maxHeight,
              child: view(autoResize: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.text, required this.color, this.onClose});
  final String text;
  final Color color;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(14, 6, onClose == null ? 14 : 4, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.4))),
        ),
        child: Row(children: [
          Expanded(child: Text(text, style: mono(context, size: 11.5, color: color))),
          if (onClose != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: color),
              onPressed: onClose,
            ),
        ]),
      );
}

/// Esc, Tab, sticky Ctrl, ^C, arrows and a few symbols, above the keyboard.
class _ExtraKeyBar extends StatelessWidget {
  const _ExtraKeyBar({
    required this.ctrlArmed,
    required this.enabled,
    required this.onKey,
    required this.onPaste,
  });
  final bool ctrlArmed;
  final bool enabled;
  final ValueChanged<ExtraKey> onKey;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, VoidCallback? onTap, {bool active = false, String? tip}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: active ? cs.primary : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              canRequestFocus: false,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minWidth: 40),
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Text(label,
                    semanticsLabel: tip,
                    style: mono(context,
                        size: 13,
                        weight: FontWeight.w600,
                        color: active ? cs.onPrimary : (onTap == null ? cs.outline : cs.onSurface))),
              ),
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final k in ExtraKey.values)
              key(k.label, enabled ? () => onKey(k) : null,
                  active: k == ExtraKey.ctrl && ctrlArmed, tip: k.name),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: IconButton(
                tooltip: 'Paste',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onPaste : null,
                icon: const Icon(Icons.content_paste, size: 18),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
