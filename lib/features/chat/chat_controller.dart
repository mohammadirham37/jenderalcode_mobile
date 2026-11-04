import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import 'chat_state.dart';
import 'composer_logic.dart';
import 'policy.dart';

typedef ChatKey = ({String desktopId, String sessionId});

/// Drives one open chat: subscribe + history on open (and again whenever the
/// link to the desktop comes back), events folded into [ChatState],
/// unsubscribe on leave.
class ChatController extends Notifier<ChatState> {
  ChatController(this.key);
  final ChatKey key;

  RpcClient? _rpc;
  final _subs = <StreamSubscription<Object?>>[];

  /// Events that arrive while `session.history` is in flight.
  List<RpcEvent>? _buffer;
  int _loadGen = 0;
  Timer? _usageDebounce;

  @override
  ChatState build() {
    final hub = ref.watch(hubProvider);
    ref.onDispose(_dispose);
    if (hub == null || !hub.isKnown(key.desktopId)) {
      return const ChatState(loading: false, loadError: 'This desktop is not paired.');
    }
    final rpc = hub.rpc(key.desktopId);
    _rpc = rpc;
    _subs.add(rpc.events.listen(_onEvent));
    _subs.add(hub.linkUp.where((id) => id == key.desktopId).listen((_) => reload()));
    Future.microtask(reload);
    return const ChatState();
  }

  void _dispose() {
    _usageDebounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final rpc = _rpc;
    if (rpc != null) {
      rpc.call('session.unsubscribe', {'session_id': key.sessionId}).ignore();
    }
  }

  void _onEvent(RpcEvent e) {
    if (e.sessionId != key.sessionId) return;
    if (e.name == 'usage') {
      _usageDebounce?.cancel();
      _usageDebounce = Timer(const Duration(milliseconds: 400), loadUsage);
    }
    final buf = _buffer;
    if (buf != null) {
      buf.add(e);
      return;
    }
    state = state.applyEvent(e, key.sessionId);
  }

  /// Subscribe first (buffering events), then load history, then replay the
  /// buffered events except deltas: history may already contain their text,
  /// and the final `message` event replaces the content anyway.
  Future<void> reload() async {
    final rpc = _rpc;
    if (rpc == null) return;
    final gen = ++_loadGen;
    _buffer = [];
    if (state.session == null) {
      state = state.copyWith(loading: true, loadError: null);
    }
    try {
      await rpc.call('session.subscribe', {'session_id': key.sessionId});
      final h = SessionHistory.fromJson(
          await rpc.call('session.history', {'session_id': key.sessionId}));
      if (!ref.mounted || gen != _loadGen) return;
      var s = state.withHistory(h);
      for (final e in _buffer ?? const <RpcEvent>[]) {
        if (e.name != 'delta') s = s.applyEvent(e, key.sessionId);
      }
      _buffer = null;
      state = s;
      loadUsage();
    } on RpcError catch (e) {
      if (!ref.mounted || gen != _loadGen) return;
      final buf = _buffer ?? const <RpcEvent>[];
      _buffer = null;
      var s = state;
      for (final ev in buf) {
        s = s.applyEvent(ev, key.sessionId);
      }
      state = s.copyWith(
        loading: false,
        loadError: state.session == null ? e.readable : null,
        lastError: state.session == null ? state.lastError : e.readable,
      );
    }
  }

  /// `session.usage` for the context meter. Errors are ignored (older
  /// desktops do not have it).
  Future<void> loadUsage() async {
    final rpc = _rpc;
    if (rpc == null) return;
    try {
      final r = await rpc.call('session.usage', {'session_id': key.sessionId});
      if (ref.mounted) state = state.copyWith(usage: SessionUsage.fromJson(r));
    } on RpcError {
      // keep the last value
    }
  }

  /// Sends a message; while a turn runs it steers instead and falls back to
  /// `chat.send` when the desktop says no turn is running. Files and images
  /// cannot steer (§6.6).
  Future<bool> send(
    String text, {
    List<String> attachments = const [],
    List<ImageAttachment> images = const [],
  }) async {
    final rpc = _rpc;
    final content = text.trim();
    final extras = attachments.isNotEmpty || images.isNotEmpty;
    if (rpc == null || (content.isEmpty && !extras) || state.sending) return false;
    if (state.busy && extras) {
      state = state.copyWith(
          lastError: 'Files and images cannot steer a running turn. Send them when it finishes.');
      return false;
    }
    state = state.copyWith(sending: true, lastError: null);
    try {
      final params = <String, dynamic>{'session_id': key.sessionId, 'content': content};
      if (attachments.isNotEmpty) params['attachments'] = attachments;
      if (images.isNotEmpty) params['images'] = [for (final i in images) i.toJson()];
      if (state.busy) {
        final r = await rpc.call('chat.steer', params);
        if (r['message_id'] == null) {
          await rpc.call('chat.send', params);
        }
      } else {
        await rpc.call('chat.send', params);
        if (ref.mounted && !state.busy) {
          state = state.copyWith(busy: true, status: 'thinking');
        }
      }
      return true;
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(lastError: e.readable);
      return false;
    } finally {
      if (ref.mounted) state = state.copyWith(sending: false);
    }
  }

  Future<void> cancel() async {
    final rpc = _rpc;
    if (rpc == null) return;
    try {
      await rpc.call('chat.cancel', {'session_id': key.sessionId});
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(lastError: e.readable);
    }
  }

  Future<void> decide(String approvalId, bool approved) async {
    final rpc = _rpc;
    if (rpc == null || state.deciding.contains(approvalId)) return;
    state = state.copyWith(deciding: {...state.deciding, approvalId});
    try {
      await rpc.call('approval.decide',
          {'approval_id': approvalId, 'approved': approved});
      if (!ref.mounted) return;
      final a = state.approvals[approvalId];
      state = state.copyWith(
        approvals: a == null || !a.isPending
            ? state.approvals
            : {...state.approvals, approvalId: a.withStatus(approved ? 'approved' : 'denied')},
        deciding: {...state.deciding}..remove(approvalId),
      );
    } on RpcError catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        lastError: e.readable,
        deciding: {...state.deciding}..remove(approvalId),
      );
    }
  }

  /// Switches the session's permission mode. Callers go through
  /// [changePolicy] so Full access is confirmed first. Returns true on success.
  Future<bool> setPolicy({
    required String mode,
    required Capabilities caps,
    required Future<bool> Function() confirmFullAccess,
  }) async {
    final rpc = _rpc;
    if (rpc == null || state.settingPolicy) return false;
    state = state.copyWith(settingPolicy: true, lastError: null);
    final r = await changePolicy(
      mode: mode,
      current: state.session?.policyMode,
      caps: caps,
      confirmFullAccess: confirmFullAccess,
      send: (m) => setSessionPolicy(rpc, key.sessionId, m),
    );
    if (!ref.mounted) return false;
    switch (r) {
      case PolicyChanged(:final session):
        state = state.copyWith(session: session, settingPolicy: false);
        return true;
      case PolicyFailed(:final error):
        state = state.copyWith(lastError: error.readable, settingPolicy: false);
      case PolicyNotSent():
        state = state.copyWith(settingPolicy: false);
    }
    return false;
  }

  /// `session.set_agent` / `session.set_model`: both answer `{session}`.
  Future<bool> updateSession(String method, Json params) async {
    final rpc = _rpc;
    if (rpc == null || state.updatingSession) return false;
    state = state.copyWith(updatingSession: true, lastError: null);
    try {
      final r = await rpc.call(method, {'session_id': key.sessionId, ...params});
      if (!ref.mounted) return false;
      final raw = r['session'];
      state = state.copyWith(
        session: raw is Map ? Session.fromJson(raw.cast<String, dynamic>()) : null,
        updatingSession: false,
      );
      return true;
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(lastError: e.readable, updatingSession: false);
      return false;
    }
  }

  Future<bool> setAgent(String agentId) =>
      updateSession('session.set_agent', {'agent_profile_id': agentId});

  Future<bool> setModel(String providerId, String modelName) =>
      updateSession('session.set_model', {'provider_id': providerId, 'model_name': modelName});

  /// `checkpoints.restore`: returns how many files were restored, or null.
  Future<int?> restoreCheckpoints() async {
    final rpc = _rpc;
    if (rpc == null) return null;
    try {
      final r = await rpc.call('checkpoints.restore', {'session_id': key.sessionId});
      return (r['restored'] as num?)?.toInt() ?? 0;
    } on RpcError catch (e) {
      if (ref.mounted) state = state.copyWith(lastError: e.readable);
      return null;
    }
  }

  void clearError() => state = state.copyWith(lastError: null);
}

final chatProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatState, ChatKey>(ChatController.new);
