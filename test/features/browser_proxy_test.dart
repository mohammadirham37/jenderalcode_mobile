import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/features/browser/browser_proxy.dart';

void main() {
  test('parses what users type in the address bar', () {
    expect(parseBrowserAddress('5173').toString(), 'http://localhost:5173/');
    expect(parseBrowserAddress('localhost:3000/app?x=1').toString(), 'http://localhost:3000/app?x=1');
    expect(parseBrowserAddress('127.0.0.1:8000').toString(), 'http://127.0.0.1:8000/');
    expect(parseBrowserAddress('https://app.localhost').toString(), 'https://app.localhost/');
    expect(parseBrowserAddress('example.com'), isNull);
    expect(parseBrowserAddress('192.168.1.2:5173'), isNull);
    expect(parseBrowserAddress('localhost.evil.com'), isNull);
    expect(parseBrowserAddress(''), isNull);
  });

  group('proxy', () {
    late BrowserProxy proxy;
    final calls = <(String, Map<String, dynamic>)>[];
    final big = List<int>.generate(1000, (i) => i % 256);

    setUp(() {
      calls.clear();
      proxy = BrowserProxy((method, params) async {
        calls.add((method, params));
        if (method == 'http.read') {
          return {'body': base64Encode(big.sublist(600)), 'done': true};
        }
        final url = Uri.parse(params['url'] as String);
        switch (url.path) {
          case '/big':
            return {'status': 200, 'headers': [['content-type', 'application/octet-stream']], 'body': base64Encode(big.sublist(0, 600)), 'stream_id': 's1'};
          case '/go':
            return {'status': 302, 'headers': [['location', 'http://localhost:${url.port}/home']], 'body': ''};
          case '/down':
            throw const RpcError('unreachable', 'Nothing is listening on http://localhost:5173 on the desktop.');
          default:
            return {
              'status': 200,
              'headers': [['content-type', 'text/html'], ['set-cookie', 'a=1'], ['set-cookie', 'b=2'], ['content-length', '999']],
              'body': base64Encode(utf8.encode('<h1>${url.path}?${url.query}</h1>')),
            };
        }
      });
    });
    tearDown(() => proxy.stop());

    Future<HttpClientResponse> get(Uri u, {Map<String, String> headers = const {}}) async {
      final c = HttpClient();
      final req = await c.getUrl(u);
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      return req.close();
    }

    test('forwards path, query and headers to the desktop origin', () async {
      final base = await proxy.start(Uri.parse('http://localhost:47811/'));
      final res = await get(base.replace(path: '/page', query: 'q=1'),
          headers: {'referer': '${base.toString().replaceAll(RegExp(r'/$'), '')}/from', 'accept-encoding': 'gzip'});
      expect(res.statusCode, 200);
      expect(await res.transform(utf8.decoder).join(), '<h1>/page?q=1</h1>');
      expect(res.headers['set-cookie'], ['a=1', 'b=2']);
      final (method, params) = calls.single;
      expect(method, 'http.request');
      expect(params['url'], 'http://localhost:47811/page?q=1');
      final sent = {for (final h in params['headers'] as List) h[0]: h[1]};
      expect(sent['referer'], 'http://localhost:47811/from');
      expect(sent.containsKey('accept-encoding'), isFalse);
      expect(sent.containsKey('host'), isFalse);
      // Same port as the target when it was free.
      expect(base.port, 47811);
      expect(proxy.toTarget(base.replace(path: '/x')).toString(), 'http://localhost:47811/x');
      expect(proxy.toLocal(Uri.parse('http://localhost:47811/y')).toString(), 'http://127.0.0.1:47811/y');
    });

    test('joins chunked responses', () async {
      final base = await proxy.start(Uri.parse('http://localhost:47812'));
      final res = await get(base.replace(path: '/big'));
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(bytes, big);
      expect(calls.map((c) => c.$1), ['http.request', 'http.read']);
    });

    test('keeps redirects on the proxy', () async {
      final base = await proxy.start(Uri.parse('http://localhost:47813'));
      final res = await get(base.replace(path: '/go'));
      expect(res.statusCode, 302);
      expect(res.headers.value('location'), 'http://127.0.0.1:47813/home');
    });

    test('shows the desktop error as a page', () async {
      final base = await proxy.start(Uri.parse('http://localhost:47814'));
      final res = await get(base.replace(path: '/down'));
      expect(res.statusCode, 502);
      expect(await res.transform(utf8.decoder).join(), contains('Nothing is listening'));
    });

    test('falls back to another port when the target port is taken', () async {
      final taken = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => taken.close(force: true));
      final base = await proxy.start(Uri.parse('http://localhost:${taken.port}'));
      expect(base.port, isNot(taken.port));
    });
  });
}
