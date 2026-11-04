import 'package:dio/dio.dart';

/// Error returned by the relay as `{"error","message"}` (docs/protocol.md §4),
/// or a transport failure (`network`).
class RelayError implements Exception {
  const RelayError(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;

  bool get isUnauthorized => code == 'unauthorized' || status == 401;

  /// Text for the UI.
  String get readable => switch (code) {
        'unauthorized' => 'Your session has expired. Sign in again.',
        'forbidden' => 'This desktop belongs to a different account.',
        'not_found' => 'Not found. The pairing code may be wrong or used.',
        'conflict' => 'This pairing code was already claimed by another phone.',
        'expired' => 'The pairing code has expired. Show a new QR code on the desktop.',
        'rate_limited' => 'Too many attempts. Wait a moment and try again.',
        'desktop_offline' =>
          'The desktop is not waiting for this pairing. Keep the QR code open on the desktop and try again.',
        'network' => 'Cannot reach the relay. Check your connection.',
        _ => message.isNotEmpty ? message : code,
      };

  @override
  String toString() => 'RelayError($code, $message)';
}

class AuthResult {
  const AuthResult({
    required this.deviceId,
    required this.deviceToken,
    this.userId,
    this.email,
    this.name,
  });
  final String deviceId;
  final String deviceToken;
  final String? userId;
  final String? email;
  final String? name;

  factory AuthResult.fromJson(Map<String, dynamic> j) {
    final user = (j['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AuthResult(
      deviceId: j['device_id'] as String,
      deviceToken: j['device_token'] as String,
      userId: user['id']?.toString(),
      email: user['email'] as String?,
      name: user['name'] as String?,
    );
  }
}

class ClaimResult {
  const ClaimResult({
    required this.pairingId,
    required this.desktopName,
    required this.desktopPublicKey,
    required this.expiresAt,
  });
  final String pairingId;
  final String desktopName;
  final String desktopPublicKey;

  /// Milliseconds since the epoch.
  final int expiresAt;

  factory ClaimResult.fromJson(Map<String, dynamic> j) => ClaimResult(
        pairingId: j['pairing_id'] as String,
        desktopName: j['desktop_name'] as String? ?? '',
        desktopPublicKey: j['desktop_public_key'] as String,
        expiresAt: (j['expires_at'] as num).toInt(),
      );
}

class Peer {
  const Peer({
    required this.deviceId,
    required this.kind,
    required this.name,
    required this.publicKey,
    required this.online,
    this.lastSeen,
  });
  final String deviceId;
  final String kind;
  final String name;
  final String publicKey;
  final bool online;
  final int? lastSeen;

  factory Peer.fromJson(Map<String, dynamic> j) => Peer(
        deviceId: j['device_id'] as String,
        kind: j['kind'] as String? ?? '',
        name: j['name'] as String? ?? '',
        publicKey: j['public_key'] as String? ?? '',
        online: j['online'] == true,
        lastSeen: (j['last_seen'] as num?)?.toInt(),
      );
}

/// HTTP client for the relay API (§4). The device token is sent as
/// `Authorization: Bearer <token>`.
class RelayApi {
  RelayApi({required String baseUrl, Dio? dio, this.token})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            ));

  final Dio _dio;

  /// Device token; null before login.
  String? token;

  Future<AuthResult> authGoogle({
    required String idToken,
    required String deviceName,
    required String publicKey,
  }) async =>
      AuthResult.fromJson(await _post('/v1/auth/google', {
        'id_token': idToken,
        'device_name': deviceName,
        'public_key': publicKey,
      }, auth: false));

  Future<AuthResult> authDev({
    required String email,
    required String deviceName,
    required String publicKey,
  }) async =>
      AuthResult.fromJson(await _post('/v1/auth/dev', {
        'email': email,
        'device_name': deviceName,
        'public_key': publicKey,
      }, auth: false));

  Future<ClaimResult> claimPairing(String code) async =>
      ClaimResult.fromJson(await _post('/v1/pairings/claim', {'code': code}));

  /// Returns `desktop_device_id`.
  Future<String> approvePairing(String pairingId) async {
    final j = await _post(
        '/v1/pairings/${Uri.encodeComponent(pairingId)}/approve', {});
    return j['desktop_device_id'] as String;
  }

  Future<List<Peer>> peers() async {
    final j = await _send('GET', '/v1/peers');
    final list = (j['peers'] as List?) ?? const [];
    return [for (final p in list) Peer.fromJson((p as Map).cast())];
  }

  Future<void> unpair(String deviceId) =>
      _send('DELETE', '/v1/peers/${Uri.encodeComponent(deviceId)}');

  Future<void> revokeDevice(String deviceId) =>
      _send('DELETE', '/v1/devices/${Uri.encodeComponent(deviceId)}');

  Future<Map<String, dynamic>> _post(String path, Object body,
          {bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, bool auth = true}) async {
    try {
      final res = await _dio.request<Object?>(
        path,
        data: body,
        options: Options(
          method: method,
          headers: {
            if (auth && token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      final data = res.data;
      return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    } on DioException catch (e) {
      throw errorFrom(e);
    }
  }

  static RelayError errorFrom(DioException e) {
    final res = e.response;
    if (res == null) {
      return RelayError('network', e.message ?? 'network error');
    }
    final data = res.data;
    if (data is Map && data['error'] is String) {
      return RelayError(
        data['error'] as String,
        data['message']?.toString() ?? '',
        status: res.statusCode,
      );
    }
    return RelayError(
      res.statusCode == 401 ? 'unauthorized' : 'http_${res.statusCode}',
      'HTTP ${res.statusCode}',
      status: res.statusCode,
    );
  }
}
