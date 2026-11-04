import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

import 'relay_frames.dart';

/// One open WebSocket. Abstracted so tests can use a fake.
abstract class SocketConnection {
  /// Incoming text frames; completes when the socket closes.
  Stream<String> get messages;
  void send(String text);
  Future<void> close([int? code]);
  int? get closeCode;
}

typedef SocketConnector = Future<SocketConnection> Function(Uri uri);

class _IoConnection implements SocketConnection {
  _IoConnection(this._ch);
  final IOWebSocketChannel _ch;

  @override
  Stream<String> get messages =>
      _ch.stream.where((e) => e is String).cast<String>();
  @override
  void send(String text) => _ch.sink.add(text);
  @override
  Future<void> close([int? code]) async => _ch.sink.close(code);
  @override
  int? get closeCode => _ch.closeCode;
}

Future<SocketConnection> ioConnector(Uri uri) async {
  final ch = IOWebSocketChannel.connect(
    uri,
    connectTimeout: const Duration(seconds: 10),
  );
  await ch.ready;
  return _IoConnection(ch);
}

enum SocketState {
  disconnected,
  connecting,
  ready,

  /// Another connection of this device replaced us (close code 4000).
  /// We wait for the app to resume before connecting again.
  replaced,

  /// Token rejected, or device revoked. Never reconnects.
  stopped,
}

/// Reconnect delays: 1 s, 2 s, 4 s, ... capped at 30 s (§5.1).
Duration backoffDelay(int attempt) {
  final secs = 1 << (attempt.clamp(0, 5));
  return Duration(seconds: secs > 30 ? 30 : secs);
}

/// `/v1/ws` client: sends the `auth` frame first, parses relay frames and
/// reconnects with backoff. Call [resume] when the app returns to the
/// foreground.
class RelaySocket {
  RelaySocket({
    required this.uri,
    required this.token,
    SocketConnector? connector,
    this.readyTimeout = const Duration(seconds: 15),
    Duration Function(int attempt)? backoff,
  })  : _connector = connector ?? ioConnector,
        _backoff = backoff ?? backoffDelay;

  final Uri uri;
  final String token;
  final SocketConnector _connector;
  final Duration readyTimeout;
  final Duration Function(int attempt) _backoff;

  final _frames = StreamController<RelayFrame>.broadcast();
  final _states = StreamController<SocketState>.broadcast();

  SocketConnection? _conn;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  Timer? _readyTimer;
  int _attempt = 0;
  bool _started = false;
  SocketState _state = SocketState.disconnected;

  Stream<RelayFrame> get frames => _frames.stream;
  Stream<SocketState> get states => _states.stream;
  SocketState get state => _state;
  bool get isReady => _state == SocketState.ready;

  void start() {
    if (_started) return;
    _started = true;
    _connect();
  }

  /// App came back to the foreground: reconnect now if we are down.
  void resume() {
    if (!_started || _state == SocketState.stopped) return;
    if (_state == SocketState.disconnected || _state == SocketState.replaced) {
      _retry?.cancel();
      _attempt = 0;
      _connect();
    }
  }

  /// Sends a `msg` frame. Returns false when not connected.
  bool sendMsg({required String to, required String id, required String body}) {
    final c = _conn;
    if (c == null || _state != SocketState.ready) return false;
    c.send(jsonEncode({'t': 'msg', 'to': to, 'id': id, 'body': body}));
    return true;
  }

  Future<void> dispose() async {
    _started = false;
    _setState(SocketState.stopped);
    await _teardown();
    await _frames.close();
    await _states.close();
  }

  void _setState(SocketState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> _connect() async {
    if (!_started || _state == SocketState.stopped) return;
    _retry?.cancel();
    await _teardown();
    _setState(SocketState.connecting);
    final SocketConnection conn;
    try {
      conn = await _connector(uri);
    } catch (_) {
      _scheduleRetry();
      return;
    }
    if (!_started || _state == SocketState.stopped) {
      await conn.close();
      return;
    }
    _conn = conn;
    _sub = conn.messages.listen(
      _onText,
      onDone: () => _onClosed(conn),
      onError: (_) {},
      cancelOnError: false,
    );
    conn.send(jsonEncode({'t': 'auth', 'token': token}));
    _readyTimer = Timer(readyTimeout, () {
      if (_state == SocketState.connecting) conn.close();
    });
  }

  void _onText(String text) {
    final f = parseRelayFrame(text);
    if (f == null) return;
    switch (f) {
      case ReadyFrame():
        _readyTimer?.cancel();
        _attempt = 0;
        _setState(SocketState.ready);
      case RevokedFrame():
        _setState(SocketState.stopped);
      case ErrorFrame(:final code):
        if (code == 'unauthorized' || code == 'forbidden') {
          _setState(SocketState.stopped);
        }
      default:
        break;
    }
    if (!_frames.isClosed) _frames.add(f);
  }

  void _onClosed(SocketConnection conn) {
    if (!identical(conn, _conn)) return;
    _readyTimer?.cancel();
    _conn = null;
    _sub = null;
    if (!_started || _state == SocketState.stopped) return;
    if (conn.closeCode == 4000) {
      _setState(SocketState.replaced);
      return;
    }
    _setState(SocketState.disconnected);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_started || _state == SocketState.stopped) return;
    _setState(SocketState.disconnected);
    _retry?.cancel();
    _retry = Timer(_backoff(_attempt), _connect);
    _attempt++;
  }

  Future<void> _teardown() async {
    _readyTimer?.cancel();
    final sub = _sub, conn = _conn;
    _sub = null;
    _conn = null;
    await sub?.cancel();
    await conn?.close();
  }
}
