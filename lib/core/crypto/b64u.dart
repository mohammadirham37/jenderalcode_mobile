import 'dart:convert';
import 'dart:typed_data';

/// base64url without padding (docs/protocol.md §1).
String b64u(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url with or without padding. Throws [FormatException].
Uint8List fromB64u(String s) {
  final bare = s.trim().replaceAll(RegExp(r'=+$'), '');
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(bare) || bare.length % 4 == 1) {
    throw const FormatException('invalid base64url');
  }
  return base64Url.decode(base64Url.normalize(bare));
}

String hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd hex length');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Constant-time comparison of two byte lists.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// `a ‖ 0x00 ‖ b`, used for both the HKDF salt and the AEAD AAD.
Uint8List joinIds(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  final out = Uint8List(ab.length + 1 + bb.length);
  out.setAll(0, ab);
  out[ab.length] = 0;
  out.setAll(ab.length + 1, bb);
  return out;
}
