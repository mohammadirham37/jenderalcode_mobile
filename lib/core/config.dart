/// Build-time configuration from `--dart-define`. No client ids are stored in
/// the source tree; the relay is the official one (docs/protocol.md §0).
class AppConfig {
  AppConfig._();

  /// The official relay. Desktop and phone both use it; users cannot change it.
  static const String officialRelay = 'https://backendcode.jenderalcorp.com';

  /// Base URL of the relay. Defaults to [officialRelay]; local testing can
  /// override it with `--dart-define=RELAY_URL=http://10.0.2.2:8080`.
  static const String relayUrl =
      String.fromEnvironment('RELAY_URL', defaultValue: officialRelay);

  /// Google OAuth *web* client id; the relay checks the ID token's `aud`.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Shows the email-only dev login (`POST /v1/auth/dev`) instead of Google.
  static const bool devLogin = bool.fromEnvironment('DEV_LOGIN');

  static const String appVersion = '0.1.0';

  static bool get hasRelay => relayUrl.isNotEmpty;

  /// Relay base without a trailing slash.
  static String get relayBase => relayUrl.endsWith('/')
      ? relayUrl.substring(0, relayUrl.length - 1)
      : relayUrl;

  /// `ws(s)://.../v1/ws` derived from [relayUrl].
  static Uri get relaySocketUri => socketUriFor(relayBase);

  static Uri socketUriFor(String base) {
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final path = uri.path.endsWith('/')
        ? '${uri.path}v1/ws'
        : '${uri.path}/v1/ws';
    return uri.replace(scheme: scheme, path: path);
  }
}
