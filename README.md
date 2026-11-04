# JenderalCode Mobile

Android remote for the JenderalCode desktop agent. Protocol: `docs/protocol.md`
(copy of the desktop repo's `docs/REMOTE_PROTOCOL.md`; do not edit here).

Configuration comes from `--dart-define` only:

| Define | Meaning |
|---|---|
| `RELAY_URL` | Optional. Defaults to the official relay `https://backendcode.jenderalcorp.com`; override only for local testing, e.g. `http://10.0.2.2:8080` on the emulator |
| `GOOGLE_SERVER_CLIENT_ID` | Optional. Defaults to the public Google OAuth web client ID (the relay checks `aud`) |
| `DEV_LOGIN` | `true` shows the email-only dev login (`POST /v1/auth/dev`) |

```bash
flutter run --dart-define=RELAY_URL=http://10.0.2.2:8080 --dart-define=DEV_LOGIN=true
flutter run
flutter analyze && flutter test
flutter build apk --debug
```

Cleartext HTTP is allowed only in debug builds (`android/app/src/debug/AndroidManifest.xml`).

## Release build

Release APKs are signed with a key that never enters this repo. Point
`JCODE_KEY_PROPERTIES` at a `key.properties` file (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`) kept outside the repo, then:

```bash
JCODE_KEY_PROPERTIES=/path/outside/repo/key.properties \
  flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<google-web-client-id>
```

Google Sign-In only works when the signing key's SHA-1 is registered as an
Android OAuth client (package `com.jenderalcode.mobile`) in the same Google
Cloud project as the web client ID.
