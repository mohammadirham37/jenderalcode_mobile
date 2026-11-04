import '../../core/crypto/b64u.dart';
import '../../core/crypto/keypair.dart';
import '../../core/crypto/sas.dart';
import '../../core/relay/relay_api.dart';
import '../../core/storage/secure_store.dart';
import 'qr_payload.dart';

class PairingFailure implements Exception {
  const PairingFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A claimed pairing waiting for the user to compare the code and tap
/// Connect.
class PendingPairing {
  const PendingPairing({
    required this.qr,
    required this.claim,
    required this.sas,
  });
  final QrPayload qr;
  final ClaimResult claim;

  /// 6 digits, unformatted.
  final String sas;

  bool get expired => DateTime.now().millisecondsSinceEpoch >= claim.expiresAt;
}

/// §4 `claim`: the relay's `desktop_public_key` must equal the QR's `k`.
void checkClaimKey(QrPayload qr, ClaimResult claim) {
  final List<int> fromQr, fromRelay;
  try {
    fromQr = publicKeyFromB64u(qr.desktopPublicKey);
    fromRelay = publicKeyFromB64u(claim.desktopPublicKey);
  } on CryptoFailure {
    throw const PairingFailure(
        'The relay returned an invalid desktop key. Pairing was stopped.');
  }
  if (!bytesEqual(fromQr, fromRelay)) {
    throw const PairingFailure(
        'The desktop key from the relay does not match the QR code. '
        'Pairing was stopped. Someone may be intercepting the connection.');
  }
}

class PairingService {
  PairingService(this.api, this.keys);
  final RelayApi api;
  final DeviceKeyPair keys;

  Future<PendingPairing> claim(QrPayload qr) async {
    final ClaimResult c;
    try {
      c = await api.claimPairing(qr.code);
    } on RelayError catch (e) {
      throw PairingFailure(e.readable);
    }
    checkClaimKey(qr, c);
    final sas = await computeSas(
        publicKeyFromB64u(qr.desktopPublicKey), keys.publicKey);
    return PendingPairing(qr: qr, claim: c, sas: sas);
  }

  /// `approve`, returning the desktop to store. The key stored is the one
  /// from the QR code.
  Future<PairedDesktop> approve(PendingPairing p) async {
    if (p.expired) {
      throw const PairingFailure(
          'The pairing code has expired. Show a new QR code on the desktop.');
    }
    final String desktopId;
    try {
      desktopId = await api.approvePairing(p.claim.pairingId);
    } on RelayError catch (e) {
      throw PairingFailure(e.readable);
    }
    return PairedDesktop(
      deviceId: desktopId,
      name: p.qr.desktopName,
      publicKey: p.qr.desktopPublicKey,
    );
  }
}
