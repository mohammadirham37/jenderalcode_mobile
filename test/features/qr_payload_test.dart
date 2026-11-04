import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/features/pairing/qr_payload.dart';
import 'package:jenderalcode_mobile/features/pairing/pairing_service.dart';
import 'package:jenderalcode_mobile/core/relay/relay_api.dart';

const k = 'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9_AsrhtHHw';
const code = 'q83vEjRWeJCrze8SNFZ4kA';

void main() {
  group('parsePairingQr', () {
    test('valid code with percent-encoded name', () {
      final p = parsePairingQr('jcode://pair?v=1&c=$code&k=$k&n=Irham%27s%20MacBook%20Pro');
      expect(p.code, code);
      expect(p.desktopPublicKey, k);
      expect(p.desktopName, "Irham's MacBook Pro");
    });

    test('missing name falls back to "Desktop"', () {
      expect(parsePairingQr('jcode://pair?v=1&c=$code&k=$k').desktopName, 'Desktop');
    });

    test('wrong version', () {
      expect(() => parsePairingQr('jcode://pair?v=2&c=$code&k=$k&n=x'),
          throwsA(isA<QrParseError>()));
    });

    test('missing fields', () {
      for (final s in [
        'jcode://pair?c=$code&k=$k',
        'jcode://pair?v=1&k=$k',
        'jcode://pair?v=1&c=$code',
        'jcode://pair?v=1&c=&k=$k',
      ]) {
        expect(() => parsePairingQr(s), throwsA(isA<QrParseError>()), reason: s);
      }
    });

    test('wrong scheme or host, or garbage', () {
      for (final s in [
        'https://pair?v=1&c=$code&k=$k',
        'jcode://other?v=1&c=$code&k=$k',
        'hello world',
        '',
      ]) {
        expect(() => parsePairingQr(s), throwsA(isA<QrParseError>()), reason: s);
      }
    });

    test('key must be 32 bytes of base64url', () {
      expect(() => parsePairingQr('jcode://pair?v=1&c=$code&k=AAAA'),
          throwsA(isA<QrParseError>()));
      expect(() => parsePairingQr('jcode://pair?v=1&c=$code&k=${k.replaceFirst('B', '+')}'),
          throwsA(isA<QrParseError>()));
    });

    test('optional r must match the configured relay', () {
      const url = 'https://relay.example';
      expect(parsePairingQr('jcode://pair?v=1&c=$code&k=$k&r=https%3A%2F%2Frelay.example%2F',
              relayUrl: url)
          .code, code);
      expect(() => parsePairingQr('jcode://pair?v=1&c=$code&k=$k&r=https%3A%2F%2Fevil.example',
              relayUrl: url),
          throwsA(isA<QrParseError>()));
    });
  });

  group('checkClaimKey', () {
    final qr = parsePairingQr('jcode://pair?v=1&c=$code&k=$k&n=D');
    ClaimResult claim(String key) => ClaimResult(
        pairingId: 'p', desktopName: 'D', desktopPublicKey: key, expiresAt: 0);

    test('accepts the same key', () => checkClaimKey(qr, claim(k)));

    test('aborts when the relay returns a different key', () {
      expect(() => checkClaimKey(qr, claim('ZLEBsdC-WocEvQePmJUAH8A-jp-VIvGI3RKNmEbUhGY')),
          throwsA(isA<PairingFailure>()));
      expect(() => checkClaimKey(qr, claim('nope')), throwsA(isA<PairingFailure>()));
    });
  });
}
