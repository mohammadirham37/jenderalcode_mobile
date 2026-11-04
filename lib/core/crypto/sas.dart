import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// The 6-digit verification code (docs/protocol.md §3.1), e.g. `"042917"`.
Future<String> computeSas(List<int> pkDesktop, List<int> pkMobile) async {
  final input = <int>[
    ...utf8.encode('jcode-sas-v1'),
    ...pkDesktop,
    ...pkMobile,
  ];
  final d = (await Sha256().hash(input)).bytes;
  final n = ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) % 1000000;
  return n.toString().padLeft(6, '0');
}

/// `"042917"` → `"042 917"`.
String formatSas(String sas) =>
    sas.length == 6 ? '${sas.substring(0, 3)} ${sas.substring(3)}' : sas;
