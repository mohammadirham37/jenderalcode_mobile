import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import 'extra_keys.dart';
import 'terminal_state.dart';

typedef TermKey = ({String desktopId, String terminalId});

/// Drives one open terminal: `terminal.attach` on open, after a reconnect
/// (`linkUp`) and on app resume; `terminal.data`/`exit`/`resized` folded in
/// with the reducer; output written to [emulator] at most once per frame;
/// `terminal.detach` on leave.
class TerminalSessionController extends Notifier<TermState> {
  TerminalSessionController(this.key);
  final TermKey key;

  RpcClient? _rpc;
  final _subs = <StreamSubscription<Object?>>[];
  int _attachGen = 0;

  /// The emulator for the current attach. Replaced on every attach
  /// ([TermState.generation]), so widgets must read it after a rebuild.
  Terminal emulator = Terminal(maxLines: 10000);

  final _out = StringBuffer();
  Timer? _flush;
  final _in = StringBuffer();
  bool _inScheduled = false;
  Timer? _resizeDebounce;

  @override
  TermState build() {
    final hub = ref.watch(hubProvider);
    ref.onDispose(_dispose);
    if (hub == null || !hub.isKnown(key.desktopId)) {
      return const TermState(error: 'This desktop is not paired.');
    }
    final rpc = hub.rpc(key.desktopId);
    _rpc = rpc;
    _subs.add(rpc.events.where((e) => e.name.startsWith('terminal.')).listen(_onEvent));
    // The desktop drops our attach when we go offline: attach again.
    _subs.add(hub.linkUp.where((id) => id == key.desktopId).listen((_) => attach()));
    _wire(emulator);
    Future.microtask(attach);
    return const TermState(attaching: true);
  }

  void _dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _flush?.cancel();
    _resizeDebounce?.cancel();
    _rpc?.call('terminal.detach', {'terminal_id': key.terminalId}).ignore();
  }

  void _wire(Terminal t) {
    t.onOutput = _onTyped;
    t.onResize = _onViewResize;
  }

  Future<void> attach() async {
    final rpc = _rpc;
    if (rpc == null) return;
    final gen = ++_attachGen;
    state = state.copyWith(attaching: true, error: null);
    try {
      final r = await rpc.call('terminal.attach', {'terminal_id': key.terminalId});
      if (!ref.mounted || gen != _attachGen) return;
      _apply(reduceAttach(state, r));
    } on RpcError catch (e) {
      if (!ref.mounted || gen != _attachGen) return;
      state = state.copyWith(attaching: false, attached: false, error: e.readable);
    }
  }

  /// App came back to the foreground: the socket may have stayed up while the
  /// desktop dropped us. `terminal.attach` is idempotent, so just attach again.
  Future<void> reattach() => attach();

  void _onEvent(RpcEvent e) {
    if (e.data['terminal_id'] != key.terminalId) return;
    // Output from before the attach answered is already in its scrollback.
    if (state.attaching && e.name == 'terminal.data') return;
    _apply(reduceEvent(state, e, key.terminalId));
  }

  void _apply(TermUpdate u) {
    final prev = state;
    if (u.reset) {
      _flush?.cancel();
      _flush = null;
      _out.clear();
      final t = Terminal(maxLines: 10000);
      _wire(t);
      t.resize(u.state.cols, u.state.rows);
      emulator = t;
    } else if (u.state.info != null &&
        prev.info != null &&
        (u.state.cols != prev.cols || u.state.rows != prev.rows) &&
        !u.state.info!.isRemote) {
      // Desktop tab resized: follow it.
      _flushNow();
      emulator.resize(u.state.cols, u.state.rows);
    }
    if (u.output.isNotEmpty) {
      _out.write(u.output);
      _flush ??= Timer(const Duration(milliseconds: 16), _flushNow);
    }
    if (!identical(u.state, prev)) state = u.state;
  }

  void _flushNow() {
    _flush?.cancel();
    _flush = null;
    if (_out.isEmpty) return;
    final s = _out.toString();
    _out.clear();
    emulator.write(s);
  }

  // ---- input ----

  void _onTyped(String data) {
    if (state.ctrlArmed) {
      state = state.copyWith(ctrlArmed: false);
      data = applyCtrl(data);
    }
    sendInput(data);
  }

  void toggleCtrl() => state = state.copyWith(ctrlArmed: !state.ctrlArmed);

  void pressKey(ExtraKey k) {
    if (k == ExtraKey.ctrl) {
      toggleCtrl();
      return;
    }
    final seq = extraKeySequence(k, ctrl: state.ctrlArmed, appCursor: emulator.cursorKeysMode);
    if (state.ctrlArmed) state = state.copyWith(ctrlArmed: false);
    if (seq != null) sendInput(seq);
  }

  /// Uses the emulator so bracketed paste applies when the program asked.
  void paste(String text) {
    if (text.isEmpty) return;
    if (state.ctrlArmed) state = state.copyWith(ctrlArmed: false);
    emulator.paste(text);
  }

  /// Queues [data] for `terminal.input`; keys typed in the same tick go out
  /// as one request, in order.
  void sendInput(String data) {
    if (data.isEmpty || state.exited) return;
    _in.write(data);
    if (_inScheduled) return;
    _inScheduled = true;
    scheduleMicrotask(() {
      _inScheduled = false;
      final all = _in.toString();
      _in.clear();
      final rpc = _rpc;
      if (rpc == null || all.isEmpty) return;
      for (final part in chunkInput(all)) {
        rpc
            .call('terminal.input', {'terminal_id': key.terminalId, 'data': part})
            .then((_) {}, onError: _onRequestError);
      }
    });
  }

  void _onRequestError(Object e) {
    if (!ref.mounted) return;
    state = state.copyWith(error: e is RpcError ? e.readable : '$e');
  }

  // ---- size ----

  /// The view measured a new grid. Only phone-opened terminals follow the
  /// phone's size; desktop tabs keep the desktop's cols/rows.
  void _onViewResize(int cols, int rows, int pw, int ph) {
    final info = state.info;
    if (info == null || !info.isRemote || state.exited) return;
    if (cols == info.cols && rows == info.rows) return;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
      final rpc = _rpc;
      final cur = state.info;
      if (rpc == null || cur == null || !ref.mounted) return;
      state = state.copyWith(info: cur.withSize(cols, rows));
      rpc.call('terminal.resize', {'terminal_id': key.terminalId, 'cols': cols, 'rows': rows}).then(
          (_) {},
          onError: _onRequestError);
    });
  }

  /// `terminal.close` (phone-opened terminals only). Returns true when closed.
  Future<bool> close() async {
    final rpc = _rpc;
    final info = state.info;
    if (rpc == null || info == null || !info.isRemote) return false;
    try {
      await rpc.call('terminal.close', {'terminal_id': key.terminalId});
      return true;
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e.readable);
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

final terminalSessionProvider = NotifierProvider.autoDispose
    .family<TerminalSessionController, TermState, TermKey>(TerminalSessionController.new);

/// `terminal.list` for one desktop.
final terminalsProvider =
    FutureProvider.autoDispose.family<List<RemoteTerminal>, String>((ref, desktopId) async {
  final hub = ref.watch(hubProvider);
  if (hub == null || !hub.isKnown(desktopId)) {
    throw const RpcError('not_paired', 'This desktop is not paired.');
  }
  final r = await hub.rpc(desktopId).call('terminal.list');
  return RemoteTerminal.listFrom(r['terminals']);
}, retry: (_, _) => null);

/// `terminal.open` in [workspaceId] with the phone's grid.
Future<RemoteTerminal> openTerminal(
    RpcClient rpc, String workspaceId, int cols, int rows) async {
  final r = await rpc.call('terminal.open', {'workspace_id': workspaceId, 'cols': cols, 'rows': rows});
  final raw = r['terminal'];
  if (raw is! Map) throw const RpcError('internal', 'The desktop sent no terminal.');
  return RemoteTerminal.fromJson(raw.cast<String, dynamic>());
}
