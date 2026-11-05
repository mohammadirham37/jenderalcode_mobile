import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Sends one request to the desktop (`RpcClient.call`).
typedef RpcCall = Future<Json> Function(String method, Json params);

/// Largest request body sent to the desktop (one relay frame, §6.10).
const maxProxyRequestBody = 384 * 1024;

/// A local HTTP server for the phone's WebView (§6.10). Every request is
/// forwarded to the desktop as `http.request`, which fetches it from the dev
/// server on the computer; large responses arrive in `http.read` chunks.
///
/// It listens on `127.0.0.1` with the target's port when that port is free,
/// so absolute `http://localhost:<port>/…` URLs in the page also come here.
class BrowserProxy {
  BrowserProxy(this._call);
  final RpcCall _call;
  HttpServer? _server;
  Uri? _target;

  /// The page origin being shown (on the desktop), e.g. `http://localhost:5173`.
  Uri? get target => _target;

  /// Where the WebView loads from, e.g. `http://127.0.0.1:5173`.
  Uri? get base {
    final s = _server;
    return s == null ? null : Uri(scheme: 'http', host: '127.0.0.1', port: s.port);
  }

  /// Serves [target]'s origin (scheme, host and port). Restarts when the
  /// origin changes; returns the local base URL.
  Future<Uri> start(Uri target) async {
    final origin = Uri(scheme: target.scheme, host: target.host, port: target.port);
    if (_server != null && _target == origin) return base!;
    await stop();
    final wanted = origin.hasPort ? origin.port : (origin.scheme == 'https' ? 443 : 80);
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, wanted);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    server.autoCompress = false;
    _server = server;
    _target = origin;
    server.listen((req) => unawaited(_handle(req)));
    return base!;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _target = null;
    await s?.close(force: true);
  }

  /// The desktop URL for a local one (for the address bar), or null.
  Uri? toTarget(Uri local) {
    final b = base, t = _target;
    if (b == null || t == null || local.host != b.host || local.port != b.port) return null;
    return t.replace(path: local.path, query: local.hasQuery ? local.query : null, fragment: local.hasFragment ? local.fragment : null);
  }

  /// The local URL for a desktop one on the served origin, or null.
  Uri? toLocal(Uri target) {
    final b = base, t = _target;
    if (b == null || t == null || !sameOrigin(target, t)) return null;
    return b.replace(path: target.path, query: target.hasQuery ? target.query : null, fragment: target.hasFragment ? target.fragment : null);
  }

  static bool sameOrigin(Uri a, Uri b) => a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  String _swap(String v, Uri from, Uri to) => v.replaceAll(_originOf(from), _originOf(to));

  static String _originOf(Uri u) => Uri(scheme: u.scheme, host: u.host, port: u.port).toString();

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final t = _target, b = base;
    if (t == null || b == null) {
      res.statusCode = HttpStatus.serviceUnavailable;
      await res.close();
      return;
    }
    try {
      final body = await _readBody(req);
      if (body == null) {
        await _fail(res, HttpStatus.requestEntityTooLarge, 'The request is too large to send to the desktop.');
        return;
      }
      final headers = <List<String>>[];
      req.headers.forEach((name, values) {
        if (_skipRequest.contains(name)) return;
        for (final v in values) {
          // The page thinks it is on the desktop's origin.
          headers.add([name, (name == 'origin' || name == 'referer') ? _swap(v, b, t) : v]);
        }
      });
      final url = t.replace(path: req.uri.path, query: req.uri.hasQuery ? req.uri.query : null);
      final r = await _call('http.request', {
        'url': url.toString(),
        'method': req.method,
        'headers': headers,
        if (body.isNotEmpty) 'body': base64Encode(body),
      });
      res.statusCode = (r['status'] as num?)?.toInt() ?? 502;
      for (final h in (r['headers'] as List? ?? const [])) {
        if (h is! List || h.length < 2) continue;
        final name = '${h[0]}'.toLowerCase();
        if (_skipResponse.contains(name)) continue;
        var value = '${h[1]}';
        if (name == 'location') value = _swap(value, t, b);
        res.headers.add(name, value, preserveHeaderCase: false);
      }
      res.add(base64Decode(r['body'] as String? ?? ''));
      var stream = r['stream_id'] as String?;
      while (stream != null) {
        final next = await _call('http.read', {'stream_id': stream});
        res.add(base64Decode(next['body'] as String? ?? ''));
        if (next['done'] == true) stream = null;
      }
      await res.close();
    } on RpcError catch (e) {
      await _fail(res, HttpStatus.badGateway, e.readable);
    } catch (e) {
      await _fail(res, HttpStatus.badGateway, '$e');
    }
  }

  Future<Uint8List?> _readBody(HttpRequest req) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in req) {
      b.add(chunk);
      if (b.length > maxProxyRequestBody) return null;
    }
    return b.takeBytes();
  }

  Future<void> _fail(HttpResponse res, int status, String message) async {
    try {
      res.statusCode = status;
      res.headers.contentType = ContentType.html;
      res.write(errorPage(message));
      await res.close();
    } catch (_) {
      // Headers already sent (failure mid-body): just drop the connection.
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// A small page explaining why the request failed.
  static String errorPage(String message) {
    const esc = HtmlEscape();
    return '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<body style="font-family:sans-serif;padding:24px;color:#39433f;background:#f5f7f6">'
        '<h3 style="margin:0 0 8px">Page not available</h3>'
        '<p style="line-height:1.5">${esc.convert(message)}</p></body>';
  }

  static const _skipRequest = {
    'host',
    'connection',
    'keep-alive',
    'proxy-connection',
    'transfer-encoding',
    'upgrade',
    'te',
    'content-length',
    'accept-encoding',
  };

  static const _skipResponse = {
    'connection',
    'keep-alive',
    'transfer-encoding',
    'content-length',
    'upgrade',
  };
}

/// What the user typed in the address bar, as a desktop URL: `5173`,
/// `localhost:5173/app`, `127.0.0.1:8000` or a full http(s) URL. Null when
/// it is not a loopback address (the desktop would refuse it).
Uri? parseBrowserAddress(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{1,5}$').hasMatch(s)) s = 'localhost:$s';
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return null;
  final h = u.host.toLowerCase();
  final loopback = h == 'localhost' || h.endsWith('.localhost') || h == '::1' || RegExp(r'^127\.\d+\.\d+\.\d+$').hasMatch(h);
  if (!loopback) return null;
  return u.path.isEmpty ? u.replace(path: '/') : u;
}
