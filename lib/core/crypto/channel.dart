import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'b64u.dart';
import 'keypair.dart';
import 'replay_guard.dart';

const int nonceLength = 24;
const int tagLength = 16;

enum Side { desktop, mobile }

/// Output of the key schedule (docs/protocol.md §3.2), exposed for tests.
class DerivedKeys {
  const DerivedKeys(this.shared, this.d2m, this.m2d);
  final Uint8List shared;
  final Uint8List d2m;
  final Uint8List m2d;
}

final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _aead = Xchacha20.poly1305Aead();

Future<DerivedKeys> deriveKeys(
  DeviceKeyPair own,
  List<int> peerPublic,
  String desktopId,
  String mobileId,
) async {
  final shared = await own.sharedSecret(peerPublic);
  final salt = joinIds(desktopId, mobileId);
  Future<Uint8List> expand(String info) async {
    final k = await _hkdf.deriveKey(
      secretKey: SecretKey(shared),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await k.extractBytes());
  }

  return DerivedKeys(
    shared,
    await expand('jcode-remote-v1 d2m'),
    await expand('jcode-remote-v1 m2d'),
  );
}

/// Sealing/opening state for one desktop ↔ phone pair (§3.3, §3.4).
class RemoteChannel {
  RemoteChannel._(this.selfId, this.peerId, this._send, this._recv);

  final String selfId;
  final String peerId;
  final SecretKey _send;
  final SecretKey _recv;

  /// `desktopId` / `mobileId` are the relay device ids of the pair.
  static Future<RemoteChannel> create({
    required DeviceKeyPair own,
    required List<int> peerPublic,
    required Side side,
    required String desktopId,
    required String mobileId,
  }) async {
    final keys = await deriveKeys(own, peerPublic, desktopId, mobileId);
    return switch (side) {
      Side.desktop => RemoteChannel._(
          desktopId, mobileId, SecretKey(keys.d2m), SecretKey(keys.m2d)),
      Side.mobile => RemoteChannel._(
          mobileId, desktopId, SecretKey(keys.m2d), SecretKey(keys.d2m)),
    };
  }

  /// `b64u(nonce ‖ ciphertext ‖ tag)`.
  Future<String> seal(List<int> plaintext, {List<int>? nonce}) async {
    final n = nonce ?? randomBytes(nonceLength);
    if (n.length != nonceLength) throw ArgumentError('nonce must be 24 bytes');
    final box = await _aead.encrypt(
      plaintext,
      secretKey: _send,
      nonce: n,
      aad: joinIds(selfId, peerId),
    );
    final out = BytesBuilder(copy: false)
      ..add(n)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return b64u(out.takeBytes());
  }

  /// Opens a body sealed by the peer. Throws [CryptoFailure].
  Future<Uint8List> open(String body) async {
    final Uint8List raw;
    try {
      raw = fromB64u(body);
    } on FormatException {
      throw const CryptoFailure('invalid base64url');
    }
    if (raw.length < nonceLength + tagLength) {
      throw const CryptoFailure('sealed body too short');
    }
    final box = SecretBox(
      raw.sublist(nonceLength, raw.length - tagLength),
      nonce: raw.sublist(0, nonceLength),
      mac: Mac(raw.sublist(raw.length - tagLength)),
    );
    try {
      final plain = await _aead.decrypt(
        box,
        secretKey: _recv,
        aad: joinIds(peerId, selfId),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const CryptoFailure('message could not be decrypted');
    }
  }

  /// Wraps an application message and seals it.
  Future<String> sealApp(Object? m, int nowMs) {
    final plain = jsonEncode({
      'v': 1,
      'ts': nowMs,
      'mid': hexEncode(randomBytes(16)),
      'm': m,
    });
    return seal(utf8.encode(plain));
  }

  /// Opens, checks version, clock skew and replays, and returns `m`.
  Future<Object?> openApp(String body, int nowMs, ReplayGuard guard) async {
    final plain = await open(body);
    final Object? v;
    try {
      v = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const CryptoFailure('plaintext is not JSON');
    }
    if (v is! Map<String, dynamic>) {
      throw const CryptoFailure('plaintext is not an object');
    }
    if (v['v'] != 1) throw const CryptoFailure('unsupported message version');
    final ts = v['ts'];
    final mid = v['mid'];
    if (ts is! int) throw const CryptoFailure('missing ts');
    if (mid is! String) throw const CryptoFailure('missing mid');
    guard.check(mid, ts, nowMs);
    return v['m'];
  }
}
