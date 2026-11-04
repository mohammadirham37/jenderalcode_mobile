import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/crypto/b64u.dart';
import 'package:jenderalcode_mobile/core/crypto/channel.dart';
import 'package:jenderalcode_mobile/core/crypto/keypair.dart';
import 'package:jenderalcode_mobile/core/crypto/replay_guard.dart';
import 'package:jenderalcode_mobile/core/crypto/sas.dart';

void main() {
  final v = jsonDecode(
    File('test/fixtures/remote-test-vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final desktopId = v['desktop_device_id'] as String;
  final mobileId = v['mobile_device_id'] as String;
  final plaintext = v['plaintext'] as String;

  late DeviceKeyPair d;
  late DeviceKeyPair m;
  late RemoteChannel dc;
  late RemoteChannel mc;

  setUpAll(() async {
    d = await DeviceKeyPair.fromSecretBytes(hexDecode(v['desktop_secret_hex']));
    m = await DeviceKeyPair.fromSecretBytes(hexDecode(v['mobile_secret_hex']));
    dc = await RemoteChannel.create(
      own: d, peerPublic: m.publicKey, side: Side.desktop,
      desktopId: desktopId, mobileId: mobileId,
    );
    mc = await RemoteChannel.create(
      own: m, peerPublic: d.publicKey, side: Side.mobile,
      desktopId: desktopId, mobileId: mobileId,
    );
  });

  group('test vectors (docs/protocol.md §3.5)', () {
    test('public keys', () {
      expect(d.publicB64u, v['desktop_public_b64u']);
      expect(m.publicB64u, v['mobile_public_b64u']);
      expect(d.publicB64u.length, 43);
    });

    test('shared secret matches from both sides', () async {
      expect(hexEncode(await d.sharedSecret(m.publicKey)), v['shared_hex']);
      expect(hexEncode(await m.sharedSecret(d.publicKey)), v['shared_hex']);
    });

    test('directional keys', () async {
      final k = await deriveKeys(m, d.publicKey, desktopId, mobileId);
      expect(hexEncode(k.shared), v['shared_hex']);
      expect(hexEncode(k.d2m), v['key_d2m_hex']);
      expect(hexEncode(k.m2d), v['key_m2d_hex']);
    });

    test('sas', () async {
      expect(await computeSas(d.publicKey, m.publicKey), v['sas']);
      expect(formatSas(v['sas'] as String), '235 517');
    });

    test('body_d2m and body_m2d', () async {
      expect(
        await dc.seal(utf8.encode(plaintext), nonce: hexDecode(v['nonce_d2m_hex'])),
        v['body_d2m'],
      );
      expect(
        await mc.seal(utf8.encode(plaintext), nonce: hexDecode(v['nonce_m2d_hex'])),
        v['body_m2d'],
      );
    });

    test('mobile opens body_d2m; desktop opens body_m2d', () async {
      expect(utf8.decode(await mc.open(v['body_d2m'])), plaintext);
      expect(utf8.decode(await dc.open(v['body_m2d'])), plaintext);
    });

    test('openApp on the vector returns m', () async {
      final guard = ReplayGuard();
      final res = await mc.openApp(v['body_d2m'], 1730000000000 + 5, guard)
          as Map<String, dynamic>;
      expect(res['method'], 'hello');
      expect(res['params'], {'app_version': '0.1.0'});
    });
  });

  group('rejections', () {
    test('tampered tag, ciphertext and nonce fail', () async {
      final raw = fromB64u(v['body_d2m']);
      for (final i in [raw.length - 1, 30, 0]) {
        final t = List<int>.of(raw)..[i] ^= 1;
        await expectLater(mc.open(b64u(t)), throwsA(isA<CryptoFailure>()));
      }
    });

    test('mobile cannot open its own message (direction / AAD)', () async {
      await expectLater(mc.open(v['body_m2d']), throwsA(isA<CryptoFailure>()));
    });

    test('swapped device ids fail', () async {
      final swapped = await RemoteChannel.create(
        own: m, peerPublic: d.publicKey, side: Side.mobile,
        desktopId: desktopId, mobileId: 'other-mobile',
      );
      await expectLater(swapped.open(v['body_d2m']), throwsA(isA<CryptoFailure>()));
    });

    test('short or malformed bodies fail', () async {
      await expectLater(mc.open('short'), throwsA(isA<CryptoFailure>()));
      await expectLater(mc.open('***'), throwsA(isA<CryptoFailure>()));
    });

    test('all-zero shared secret is rejected', () async {
      await expectLater(
        m.sharedSecret(List<int>.filled(32, 0)),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('random keys round-trip and storage form restores', () async {
      final a = await DeviceKeyPair.generate();
      final restored = await DeviceKeyPair.fromSecretB64u(a.secretB64u);
      expect(restored.publicB64u, a.publicB64u);
      expect(() => publicKeyFromB64u('AAAA'), throwsA(isA<CryptoFailure>()));
    });
  });

  group('openApp anti-replay', () {
    const now = 1730000000000;

    test('replays and stale timestamps are rejected', () async {
      final guard = ReplayGuard();
      final body = await dc.sealApp({'t': 'res', 'id': '1'}, now);
      final got = await mc.openApp(body, now + 10, guard) as Map;
      expect(got['id'], '1');
      await expectLater(mc.openApp(body, now + 20, guard),
          throwsA(isA<ReplayRejected>()));
      final stale = await dc.sealApp({}, now - maxSkewMs - 1);
      await expectLater(mc.openApp(stale, now, guard),
          throwsA(isA<ReplayRejected>()));
      final future = await dc.sealApp({}, now + maxSkewMs + 1);
      await expectLater(mc.openApp(future, now, guard),
          throwsA(isA<ReplayRejected>()));
    });

    test('wrong version is rejected', () async {
      final body = await dc.seal(utf8.encode(
          jsonEncode({'v': 2, 'ts': now, 'mid': 'aa', 'm': {}})));
      await expectLater(mc.openApp(body, now, ReplayGuard()),
          throwsA(isA<CryptoFailure>()));
    });
  });

  group('ReplayGuard', () {
    const now = 1730000000000;
    test('skew boundary is inclusive at 60 s', () {
      final g = ReplayGuard();
      g.check('a', now - maxSkewMs, now);
      g.check('b', now + maxSkewMs, now);
      expect(() => g.check('c', now - maxSkewMs - 1, now),
          throwsA(isA<ReplayRejected>()));
    });

    test('ids expire after the 120 s window', () {
      final g = ReplayGuard();
      g.check('a', now, now);
      expect(() => g.check('a', now, now + 1000), throwsA(isA<ReplayRejected>()));
      final later = now + replayWindowMs + 1;
      g.check('b', later, later);
      expect(g.remembers('a'), isFalse);
      g.check('a', later, later);
    });
  });
}
