import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value interface so tests can use an in-memory store.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// A desktop confirmed through QR + SAS. [publicKey] comes from the QR code
/// and is the only key this app ever uses for that desktop.
class PairedDesktop {
  const PairedDesktop({
    required this.deviceId,
    required this.name,
    required this.publicKey,
  });

  final String deviceId;
  final String name;

  /// b64u X25519 public key.
  final String publicKey;

  Map<String, dynamic> toJson() =>
      {'device_id': deviceId, 'name': name, 'public_key': publicKey};

  factory PairedDesktop.fromJson(Map<String, dynamic> j) => PairedDesktop(
        deviceId: j['device_id'] as String,
        name: j['name'] as String? ?? 'Desktop',
        publicKey: j['public_key'] as String,
      );
}

class StoredAccount {
  const StoredAccount({
    required this.deviceId,
    required this.deviceToken,
    this.email,
    this.name,
  });
  final String deviceId;
  final String deviceToken;
  final String? email;
  final String? name;
}

/// Everything this app persists, all in the OS secret store.
class AppStorage {
  AppStorage(this._kv);
  final KeyValueStore _kv;

  static const _kDeviceId = 'device_id';
  static const _kDeviceToken = 'device_token';
  static const _kEmail = 'user_email';
  static const _kName = 'user_name';
  static const _kSecret = 'x25519_secret';
  static const _kDesktops = 'paired_desktops';

  Future<String?> readSecretKey() => _kv.read(_kSecret);
  Future<void> writeSecretKey(String b64u) => _kv.write(_kSecret, b64u);
  Future<void> deleteSecretKey() => _kv.delete(_kSecret);

  Future<StoredAccount?> readAccount() async {
    final id = await _kv.read(_kDeviceId);
    final token = await _kv.read(_kDeviceToken);
    if (id == null || token == null) return null;
    return StoredAccount(
      deviceId: id,
      deviceToken: token,
      email: await _kv.read(_kEmail),
      name: await _kv.read(_kName),
    );
  }

  Future<void> writeAccount(StoredAccount a) async {
    await _kv.write(_kDeviceId, a.deviceId);
    await _kv.write(_kDeviceToken, a.deviceToken);
    if (a.email != null) await _kv.write(_kEmail, a.email!);
    if (a.name != null) await _kv.write(_kName, a.name!);
  }

  Future<void> clearAccount() async {
    for (final k in [_kDeviceId, _kDeviceToken, _kEmail, _kName, _kDesktops]) {
      await _kv.delete(k);
    }
  }

  Future<List<PairedDesktop>> readDesktops() async {
    final raw = await _kv.read(_kDesktops);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list) PairedDesktop.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeDesktops(List<PairedDesktop> list) => _kv.write(
      _kDesktops, jsonEncode([for (final d in list) d.toJson()]));
}
