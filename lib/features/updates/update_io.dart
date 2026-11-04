import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'update_logic.dart';

/// Lowercase hex SHA-256 of a file, streamed.
Future<String> sha256OfFile(File f) async => (await sha256.bind(f.openRead()).first).toString();

/// Checks [apk] against [sums]; deletes it and rethrows on any mismatch, so
/// an unverified file never stays around to be installed.
Future<void> verifyDownloadedApk(File apk, String sums, {String fileName = apkAssetName}) async {
  try {
    verifyChecksum(sums: sums, fileName: fileName, actualHex: await sha256OfFile(apk));
  } catch (_) {
    if (apk.existsSync()) apk.deleteSync();
    rethrow;
  }
}

/// MainActivity's "jenderalcode/updates" channel.
class UpdateBridge {
  UpdateBridge() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'installStatus') {
        final a = (call.arguments as Map?) ?? const {};
        onInstallStatus?.call('${a['status']}', a['message'] as String?);
      }
    });
  }

  static const _ch = MethodChannel('jenderalcode/updates');

  /// success | cancelled | pending_user_action | blocked | conflict | … | failure
  void Function(String status, String? message)? onInstallStatus;

  Future<String> updatesDir() async => (await _ch.invokeMethod<String>('updatesDir'))!;
  Future<bool> canRequestPackageInstalls() async =>
      await _ch.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
  Future<void> openInstallSettings() => _ch.invokeMethod('openInstallSettings');

  /// Returns "session" (PackageInstaller) or "view" (system installer screen).
  Future<String?> installApk(String path) => _ch.invokeMethod<String>('installApk', {'path': path});
}
