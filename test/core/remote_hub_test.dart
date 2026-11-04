import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/config.dart';
import 'package:jenderalcode_mobile/core/crypto/channel.dart';
import 'package:jenderalcode_mobile/core/crypto/keypair.dart';
import 'package:jenderalcode_mobile/core/relay/relay_frames.dart';
import 'package:jenderalcode_mobile/core/relay/relay_socket.dart';
import 'package:jenderalcode_mobile/core/rpc/remote_hub.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/core/storage/secure_store.dart';

const desktopId = '0b7d6c55-1f43-4b8e-9d2a-6f1e2c3d4a5b';
const mobileId = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';

class FakeConn implements SocketConnection {
  final incoming = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  int? code;
  bool closed = false;

  @override
  Stream<String> get messages => incoming.stream;
  @override
  void send(String text) => sent.add(jsonDecode(text) as Map<String, dynamic>);
  @override
  Future<void> close([int? c]) async {
    if (closed) return;
    closed = true;
    code ??= c;
    await incoming.close();
  }

  @override
  int? get closeCode => code;

  void push(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));

  /// Simulates the relay closing the socket.
  Future<void> drop([int? c]) async {
    code = c;
    await close();
  }
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('backoff is 1 s doubling to 30 s', () {
    expect([for (var i = 0; i < 7; i++) backoffDelay(i).inSeconds], [1, 2, 4, 8, 16, 30, 30]);
  });

  test('socket uri is derived from RELAY_URL', () {
    expect(AppConfig.socketUriFor('http://10.0.2.2:8080').toString(), 'ws://10.0.2.2:8080/v1/ws');
    expect(AppConfig.socketUriFor('https://r.example/base').toString(), 'wss://r.example/base/v1/ws');
  });

  test('parseRelayFrame ignores unknown and invalid frames', () {
    expect(parseRelayFrame('{"t":"future_thing"}'), isNull);
    expect(parseRelayFrame('not json'), isNull);
    expect(parseRelayFrame('{"t":"msg","from":"a"}'), isNull);
    expect(parseRelayFrame('{"t":"revoked"}'), isA<RevokedFrame>());
  });

  group('hub over a fake relay', () {
    late DeviceKeyPair desktopKeys;
    late DeviceKeyPair mobileKeys;
    late RemoteChannel desktopSide;
    late List<FakeConn> conns;
    late RelaySocket socket;
    late RemoteHub hub;

    setUp(() async {
      desktopKeys = await DeviceKeyPair.generate();
      mobileKeys = await DeviceKeyPair.generate();
      desktopSide = await RemoteChannel.create(
        own: desktopKeys, peerPublic: mobileKeys.publicKey, side: Side.desktop,
        desktopId: desktopId, mobileId: mobileId,
      );
      conns = [];
      socket = RelaySocket(
        uri: Uri.parse('ws://relay.test/v1/ws'),
        token: 'tok',
        connector: (_) async {
          final c = FakeConn();
          conns.add(c);
          return c;
        },
        backoff: (_) => const Duration(milliseconds: 10),
      );
      hub = RemoteHub(
        socket: socket,
        keys: mobileKeys,
        selfId: mobileId,
        desktops: [
          PairedDesktop(deviceId: desktopId, name: 'D', publicKey: desktopKeys.publicB64u),
        ],
        rpcTimeout: const Duration(milliseconds: 300),
      );
    });

    tearDown(() => hub.dispose());

    /// Desktop side: open the request the phone sent, reply with [result].
    Future<Map<String, dynamic>> answer(FakeConn c, Map<String, dynamic> Function(Map req) reply) async {
      final frame = c.sent.lastWhere((f) => f['t'] == 'msg');
      expect(frame['to'], desktopId);
      final plain = jsonDecode(utf8.decode(await desktopSide.open(frame['body'] as String))) as Map;
      expect(plain['v'], 1);
      expect((plain['mid'] as String).length, 32);
      final req = plain['m'] as Map;
      final body = await desktopSide.sealApp(reply(req), DateTime.now().millisecondsSinceEpoch);
      c.push({'t': 'msg', 'from': desktopId, 'id': 'e1', 'body': body});
      return req.cast();
    }

    test('auth first, ready, encrypted request/response, events', () async {
      final ups = <String>[];
      hub.linkUp.listen(ups.add);
      hub.start();
      await pump();
      final c = conns.single;
      expect(c.sent.first, {'t': 'auth', 'token': 'tok'});

      c.push({'t': 'ready', 'device_id': mobileId, 'peers': [{'device_id': desktopId, 'online': true}]});
      await pump();
      expect(socket.state, SocketState.ready);
      expect(hub.online[desktopId], isTrue);
      expect(ups, [desktopId]);

      final events = <RpcEvent>[];
      hub.rpc(desktopId).events.listen(events.add);
      final f = hub.rpc(desktopId).call('hello', {'app_version': '0.1.0'});
      await pump();
      final req = await answer(c, (r) => {
            't': 'res', 'id': r['id'], 'ok': true,
            'result': {'desktop_version': '0.1.5', 'desktop_name': 'D'},
          });
      expect(req['method'], 'hello');
      expect(req['t'], 'req');
      expect((await f)['desktop_version'], '0.1.5');

      // An event, then the very same body replayed: delivered once.
      final evBody = await desktopSide.sealApp(
          {'t': 'event', 'name': 'status', 'data': {'session_id': 's', 'status': 'idle', 'detail': null}},
          DateTime.now().millisecondsSinceEpoch);
      c.push({'t': 'msg', 'from': desktopId, 'id': 'e2', 'body': evBody});
      c.push({'t': 'msg', 'from': desktopId, 'id': 'e3', 'body': evBody});
      // Same ciphertext claimed to come from an unknown device: dropped.
      c.push({'t': 'msg', 'from': 'stranger', 'id': 'e4', 'body': evBody});
      await pump();
      await hub.drain();
      expect(events.length, 1);
      expect(events.single.name, 'status');
    });

    test('undeliverable fails the pending request fast', () async {
      hub.start();
      await pump();
      final c = conns.single;
      c.push({'t': 'ready', 'device_id': mobileId, 'peers': []});
      await pump();
      final f = hub.rpc(desktopId).call('workspaces.list');
      await pump();
      final env = c.sent.lastWhere((x) => x['t'] == 'msg')['id'] as String;
      c.push({'t': 'undeliverable', 'id': env, 'to': desktopId, 'reason': 'offline'});
      await expectLater(f, throwsA(isA<RpcError>().having((e) => e.code, 'code', 'desktop_offline')));
    });

    test('presence and unpaired are surfaced', () async {
      final unpaired = <String>[];
      final ups = <String>[];
      hub.unpaired.listen(unpaired.add);
      hub.linkUp.listen(ups.add);
      hub.start();
      await pump();
      final c = conns.single;
      c.push({'t': 'ready', 'device_id': mobileId, 'peers': [{'device_id': desktopId, 'online': false}]});
      c.push({'t': 'presence', 'device_id': desktopId, 'online': true});
      await pump();
      expect(hub.online[desktopId], isTrue);
      expect(ups, [desktopId]);
      c.push({'t': 'unpaired', 'device_id': desktopId});
      await pump();
      expect(unpaired, [desktopId]);
    });

    test('reconnects after a drop and re-sends auth', () async {
      hub.start();
      await pump();
      conns.single.push({'t': 'ready', 'device_id': mobileId, 'peers': []});
      await pump();
      await conns.single.drop(1006);
      await pump();
      expect(conns.length, 2);
      expect(conns[1].sent.first, {'t': 'auth', 'token': 'tok'});
    });

    test('close code 4000 waits for resume', () async {
      hub.start();
      await pump();
      conns.single.push({'t': 'ready', 'device_id': mobileId, 'peers': []});
      await pump();
      await conns.single.drop(4000);
      await pump();
      expect(socket.state, SocketState.replaced);
      expect(conns.length, 1);
      socket.resume();
      await pump();
      expect(conns.length, 2);
    });

    test('revoked ends the session and stops reconnecting', () async {
      final ended = <SessionEnd>[];
      hub.ended.listen(ended.add);
      hub.start();
      await pump();
      conns.single.push({'t': 'ready', 'device_id': mobileId, 'peers': []});
      conns.single.push({'t': 'revoked'});
      await pump();
      await conns.single.drop(1000);
      await pump();
      expect(ended, [SessionEnd.revoked]);
      expect(socket.state, SocketState.stopped);
      expect(conns.length, 1);
    });

    test('auth error frame ends the session', () async {
      final ended = <SessionEnd>[];
      hub.ended.listen(ended.add);
      hub.start();
      await pump();
      conns.single.push({'t': 'error', 'error': 'unauthorized'});
      await pump();
      expect(ended, [SessionEnd.unauthorized]);
    });
  });
}
