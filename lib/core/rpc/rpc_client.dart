import 'dart:async';

import 'package:uuid/uuid.dart';

import 'models.dart';

/// Application or transport error for one request (docs/protocol.md §6.1).
class RpcError implements Exception {
  const RpcError(this.code, [this.message = '']);

  /// Desktop codes: bad_request, not_found, remote_disabled, yolo_blocked,
  /// busy, internal. Local codes: timeout, offline, not_paired, closed.
  final String code;
  final String message;

  String get readable => switch (code) {
        'yolo_blocked' =>
          'This session uses Full access. Change its mode on the desktop to control it remotely.',
        'remote_disabled' => 'Remote access is turned off on the desktop.',
        'busy' => 'The desktop is busy with this session. Try again in a moment.',
        'not_found' => message.isNotEmpty ? message : 'Not found on the desktop.',
        'timeout' =>
          'The desktop did not answer. It may be offline, or it has not confirmed this phone yet.',
        'offline' => 'Not connected to the relay.',
        'not_paired' => 'The relay says this desktop is no longer paired.',
        'desktop_offline' => 'The desktop is offline.',
        _ => message.isNotEmpty ? message : 'Request failed ($code).',
      };

  @override
  String toString() => 'RpcError($code, $message)';
}

class RpcEvent {
  const RpcEvent(this.name, this.data);
  final String name;
  final Json data;
  String? get sessionId =>
      data['session_id'] is String ? data['session_id'] as String : null;
}

/// Sends one encrypted application message `m` and returns the relay
/// envelope id it went out under (so `undeliverable` can be matched).
typedef RpcTransport = Future<String> Function(Json m);

/// Request/response matching and the event stream for one desktop.
class RpcClient {
  RpcClient({
    required this.transport,
    this.timeout = const Duration(seconds: 20),
    String Function()? newId,
  }) : _newId = newId ?? (() => const Uuid().v4());

  final RpcTransport transport;
  final String Function() _newId;
  final Duration timeout;

  final _pending = <String, _Pending>{};
  final _envelopeToReq = <String, String>{};
  final _events = StreamController<RpcEvent>.broadcast();

  Stream<RpcEvent> get events => _events.stream;
  int get pendingCount => _pending.length;

  /// Sends a request and waits for its response. Throws [RpcError].
  Future<Json> call(String method, [Json params = const {}]) async {
    final id = _newId();
    final p = _Pending(Completer<Json>());
    _pending[id] = p;
    p.timer = Timer(timeout, () => _fail(id, const RpcError('timeout')));
    try {
      final env = await transport(
          {'t': 'req', 'id': id, 'method': method, 'params': params});
      if (_pending.containsKey(id)) {
        p.envelope = env;
        _envelopeToReq[env] = id;
      }
    } on RpcError catch (e) {
      _fail(id, e);
    } catch (e) {
      _fail(id, RpcError('offline', e.toString()));
    }
    return p.completer.future;
  }

  /// Handles a decrypted `m` from this desktop.
  void handleMessage(Object? m) {
    if (m is! Map) return;
    final j = m.cast<String, dynamic>();
    switch (j['t']) {
      case 'res':
        final id = j['id'];
        if (id is! String) return;
        final p = _remove(id);
        if (p == null) return;
        if (j['ok'] == true) {
          final r = j['result'];
          p.completer.complete(r is Map ? r.cast<String, dynamic>() : <String, dynamic>{});
        } else {
          final e = j['error'] is Map ? (j['error'] as Map) : const {};
          p.completer.completeError(RpcError(
            e['code'] is String ? e['code'] as String : 'internal',
            e['message'] is String ? e['message'] as String : '',
          ));
        }
      case 'event':
        final name = j['name'];
        if (name is! String) return;
        final data = j['data'];
        _events.add(RpcEvent(
            name, data is Map ? data.cast<String, dynamic>() : <String, dynamic>{}));
    }
  }

  /// The relay could not deliver envelope [envelopeId].
  void handleUndeliverable(String envelopeId, String reason) {
    final id = _envelopeToReq[envelopeId];
    if (id == null) return;
    _fail(id, RpcError(reason == 'not_paired' ? 'not_paired' : 'desktop_offline'));
  }

  void failAll(RpcError e) {
    for (final id in _pending.keys.toList()) {
      _fail(id, e);
    }
  }

  Future<void> dispose() async {
    failAll(const RpcError('closed'));
    await _events.close();
  }

  _Pending? _remove(String id) {
    final p = _pending.remove(id);
    if (p == null) return null;
    p.timer?.cancel();
    if (p.envelope != null) _envelopeToReq.remove(p.envelope);
    return p;
  }

  void _fail(String id, RpcError e) {
    final p = _remove(id);
    if (p != null && !p.completer.isCompleted) p.completer.completeError(e);
  }
}

class _Pending {
  _Pending(this.completer);
  final Completer<Json> completer;
  Timer? timer;
  String? envelope;
}
