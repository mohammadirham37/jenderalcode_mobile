import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config.dart';
import '../../core/crypto/keypair.dart';
import '../../core/providers.dart';
import '../../core/relay/relay_api.dart';
import '../../core/storage/secure_store.dart';

const deviceName = 'JenderalCode Mobile (Android)';

class AuthSession {
  const AuthSession({required this.account, required this.keys});
  final StoredAccount account;
  final DeviceKeyPair keys;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signed-in state: null when signed out.
class AuthController extends AsyncNotifier<AuthSession?> {
  static bool _googleReady = false;
  bool _loggingOut = false;

  @override
  Future<AuthSession?> build() async {
    final storage = ref.read(storageProvider);
    final account = await storage.readAccount();
    if (account == null) return null;
    final keys = await loadOrCreateKeyPair(storage);
    ref.read(relayApiProvider).token = account.deviceToken;
    return AuthSession(account: account, keys: keys);
  }

  Future<void> loginGoogle() async {
    if (AppConfig.googleServerClientId.isEmpty) {
      throw const AuthFailure(
          'GOOGLE_SERVER_CLIENT_ID is not set for this build.');
    }
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(serverClientId: AppConfig.googleServerClientId);
      _googleReady = true;
    }
    final GoogleSignInAccount user;
    try {
      user = await g.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure('Sign-in was cancelled.');
      }
      throw AuthFailure('Google sign-in failed: ${e.description ?? e.code.name}');
    }
    final idToken = user.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google did not return an ID token.');
    }
    await _finish((api, pk) =>
        api.authGoogle(idToken: idToken, deviceName: deviceName, publicKey: pk));
  }

  Future<void> loginDev(String email) => _finish((api, pk) =>
      api.authDev(email: email.trim(), deviceName: deviceName, publicKey: pk));

  Future<void> _finish(
      Future<AuthResult> Function(RelayApi api, String publicKey) call) async {
    if (!AppConfig.hasRelay) {
      throw const AuthFailure('RELAY_URL is not set for this build.');
    }
    final storage = ref.read(storageProvider);
    final keys = await loadOrCreateKeyPair(storage);
    final api = ref.read(relayApiProvider);
    final AuthResult r;
    try {
      r = await call(api, keys.publicB64u);
    } on RelayError catch (e) {
      throw AuthFailure(e.code == 'unauthorized'
          ? 'The relay rejected this sign-in.'
          : e.readable);
    }
    final account = StoredAccount(
      deviceId: r.deviceId,
      deviceToken: r.deviceToken,
      email: r.email,
      name: r.name,
    );
    await storage.writeAccount(account);
    api.token = account.deviceToken;
    state = AsyncData(AuthSession(account: account, keys: keys));
  }

  /// Revokes this device on the relay (best effort), then wipes local state.
  Future<void> logout() async {
    _loggingOut = true;
    final s = state.value;
    if (s != null) {
      try {
        await ref.read(relayApiProvider).revokeDevice(s.account.deviceId);
      } catch (_) {
        // Offline or already revoked: still sign out locally.
      }
    }
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await signOutLocally();
    _loggingOut = false;
  }

  /// Clears the account, the paired desktops and the key pair. A revoked
  /// device id is never reused, so the next sign-in gets a fresh identity.
  Future<void> signOutLocally({String? reason}) async {
    if (state.value == null) return;
    final storage = ref.read(storageProvider);
    await storage.clearAccount();
    await storage.deleteSecretKey();
    ref.read(relayApiProvider).token = null;
    if (reason != null && !_loggingOut) ref.read(authNoticeProvider.notifier).show(reason);
    state = const AsyncData(null);
  }
}

final authProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// One-off message for the login screen (e.g. "you were revoked").
class AuthNotice extends Notifier<String?> {
  @override
  String? build() => null;
  void show(String? s) => state = s;
}

final authNoticeProvider =
    NotifierProvider<AuthNotice, String?>(AuthNotice.new);
