import '../../core/crypto/keypair.dart';

/// Contents of the pairing QR code (docs/protocol.md §7):
/// `jcode://pair?v=1&c=<code>&k=<b64u pk_desktop>&n=<name>`.
class QrPayload {
  const QrPayload({
    required this.code,
    required this.desktopPublicKey,
    required this.desktopName,
  });

  final String code;

  /// b64u, exactly as in the QR (decodes to 32 bytes).
  final String desktopPublicKey;
  final String desktopName;
}

class QrParseError implements Exception {
  const QrParseError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses a scanned string. Throws [QrParseError].
///
/// [relayUrl] is this phone's relay; §7 reserves an `r` parameter that must
/// match it when present.
QrPayload parsePairingQr(String raw, {String relayUrl = ''}) {
  final Uri uri;
  try {
    uri = Uri.parse(raw.trim());
  } on FormatException {
    throw const QrParseError('This is not a JenderalCode pairing code.');
  }
  if (uri.scheme != 'jcode' || uri.host != 'pair') {
    throw const QrParseError('This is not a JenderalCode pairing code.');
  }
  final q = uri.queryParameters;
  final v = q['v'];
  if (v == null) {
    throw const QrParseError('Pairing code is missing its version.');
  }
  if (v != '1') {
    throw const QrParseError(
        'This pairing code needs a newer version of the app.');
  }
  final r = q['r'];
  if (r != null && _normRelay(r) != _normRelay(relayUrl)) {
    throw const QrParseError(
        'This desktop uses a different relay than this app.');
  }
  final c = q['c'];
  final k = q['k'];
  if (c == null || c.isEmpty) {
    throw const QrParseError('Pairing code is missing the code.');
  }
  if (k == null || k.isEmpty) {
    throw const QrParseError('Pairing code is missing the desktop key.');
  }
  try {
    publicKeyFromB64u(k);
  } on CryptoFailure {
    throw const QrParseError('Pairing code has an invalid desktop key.');
  }
  final n = q['n'];
  return QrPayload(
    code: c,
    desktopPublicKey: k,
    desktopName: (n == null || n.trim().isEmpty) ? 'Desktop' : n.trim(),
  );
}

String _normRelay(String s) {
  var t = s.trim().toLowerCase();
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}
