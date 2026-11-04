# JenderalCode Mobile

Android remote for the JenderalCode desktop agent. Protocol: `docs/protocol.md`
(copy of the desktop repo's `docs/REMOTE_PROTOCOL.md`; do not edit here).

Configuration comes from `--dart-define` only:

| Define | Meaning |
|---|---|
| `RELAY_URL` | Relay base URL, e.g. `http://10.0.2.2:8080` on the emulator |
| `GOOGLE_SERVER_CLIENT_ID` | Google OAuth web client ID (the relay checks `aud`) |
| `DEV_LOGIN` | `true` shows the email-only dev login (`POST /v1/auth/dev`) |

```bash
flutter run --dart-define=RELAY_URL=http://10.0.2.2:8080 --dart-define=DEV_LOGIN=true
flutter run --dart-define=RELAY_URL=<relay-url> --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
flutter analyze && flutter test
flutter build apk --debug
```

Cleartext HTTP is allowed only in debug builds (`android/app/src/debug/AndroidManifest.xml`).
