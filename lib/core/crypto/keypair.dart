import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'b64u.dart';

final _x25519 = X25519();

Uint8List randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/// This phone's static X25519 key pair (docs/protocol.md §2).
///
/// The 32 secret bytes are kept exactly as generated (like Rust's
/// `StaticSecret`); clamping happens inside the X25519 computation.
class DeviceKeyPair {
  DeviceKeyPair._(this._secret, this._keyPair, this.publicKey);

  final Uint8List _secret;
  final SimpleKeyPair _keyPair;

  /// The 32-byte public key.
  final Uint8List publicKey;

  static Future<DeviceKeyPair> generate() => fromSecretBytes(randomBytes(32));

  static Future<DeviceKeyPair> fromSecretBytes(List<int> secret) async {
    if (secret.length != 32) {
      throw ArgumentError('secret key must be 32 bytes');
    }
    final bytes = Uint8List.fromList(secret);
    final kp = await _x25519.newKeyPairFromSeed(bytes);
    final pub = await kp.extractPublicKey();
    return DeviceKeyPair._(bytes, kp, Uint8List.fromList(pub.bytes));
  }

  /// Restores from [secretB64u].
  static Future<DeviceKeyPair> fromSecretB64u(String s) =>
      fromSecretBytes(fromB64u(s));

  /// Storage form of the secret key. Never send it anywhere.
  String get secretB64u => b64u(_secret);

  String get publicB64u => b64u(publicKey);

  /// X25519(sk_self, pk_peer). Rejects an all-zero result (low-order point).
  Future<Uint8List> sharedSecret(List<int> peerPublic) async {
    if (peerPublic.length != 32) {
      throw const CryptoFailure('public key must be 32 bytes');
    }
    final key = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
    );
    final shared = Uint8List.fromList(await key.extractBytes());
    if (shared.every((b) => b == 0)) {
      throw const CryptoFailure('peer public key is invalid (low-order point)');
    }
    return shared;
  }
}

/// Decodes a base64url X25519 public key (must be 32 bytes).
Uint8List publicKeyFromB64u(String s) {
  final Uint8List bytes;
  try {
    bytes = fromB64u(s);
  } on FormatException {
    throw const CryptoFailure('public key is not valid base64url');
  }
  if (bytes.length != 32) {
    throw const CryptoFailure('public key must be 32 bytes');
  }
  return bytes;
}

class CryptoFailure implements Exception {
  const CryptoFailure(this.message);
  final String message;
  @override
  String toString() => 'CryptoFailure: $message';
}
