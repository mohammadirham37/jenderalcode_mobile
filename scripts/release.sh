#!/usr/bin/env bash
# Build, sign and publish an Android release of JenderalCode Mobile:
#
#   JCODE_KEY_PROPERTIES=/path/outside/repo/key.properties \
#     scripts/release.sh 1.0.1 notes.md
#
# - bumps `version:` in pubspec.yaml (x.y.z+build, build = previous + 1)
# - runs flutter analyze + flutter test
# - builds the release APK signed with the key from JCODE_KEY_PROPERTIES
#   (refuses to publish a debug-signed APK)
# - writes JenderalCode-Mobile-<x.y.z>.apk, the stable JenderalCode-Mobile.apk
#   (same bytes; the in-app updater and the desktop's QR code use it) and
#   SHA256SUMS
# - commits "Release v<x.y.z>", tags v<x.y.z>, pushes, and creates the
#   GitHub release with those three files (the release must be "latest":
#   installed apps check releases/latest)
#
# Never commit the keystore or key.properties.
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <x.y.z> <notes.md>}
NOTES=${2:?usage: scripts/release.sh <x.y.z> <notes.md>}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be x.y.z" >&2; exit 1; }
[[ -f $NOTES ]] || { echo "notes file not found: $NOTES" >&2; exit 1; }
: "${JCODE_KEY_PROPERTIES:?set JCODE_KEY_PROPERTIES to the release key.properties (outside the repo)}"
[[ -f $JCODE_KEY_PROPERTIES ]] || { echo "key.properties not found" >&2; exit 1; }

cd "$(dirname "$0")/.."
REPO=mohammadirham37/jenderalcode_mobile

if [[ -n $(git status --porcelain) ]]; then
  echo "working tree is not clean; commit or stash first" >&2
  exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "tag v$VERSION already exists" >&2
  exit 1
fi

CURRENT=$(sed -n 's/^version: *//p' pubspec.yaml)
BUILD=${CURRENT##*+}
[[ $BUILD =~ ^[0-9]+$ ]] || BUILD=0
NEXT="$VERSION+$((BUILD + 1))"
sed -i.bak "s/^version: .*/version: $NEXT/" pubspec.yaml && rm pubspec.yaml.bak
echo "version: $CURRENT -> $NEXT"

flutter analyze
flutter test
flutter build apk --release

APK=build/app/outputs/flutter-apk/app-release.apk
APKSIGNER=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/ | sort -V | tail -1)apksigner
if "$APKSIGNER" verify --print-certs "$APK" | grep -q "CN=Android Debug"; then
  echo "the APK is signed with the debug key; check JCODE_KEY_PROPERTIES" >&2
  git checkout pubspec.yaml
  exit 1
fi

OUT=$(mktemp -d)
cp "$APK" "$OUT/JenderalCode-Mobile-$VERSION.apk"
cp "$APK" "$OUT/JenderalCode-Mobile.apk"
(cd "$OUT" && shasum -a 256 "JenderalCode-Mobile-$VERSION.apk" JenderalCode-Mobile.apk > SHA256SUMS)
cat "$OUT/SHA256SUMS"

git add pubspec.yaml
git commit -m "Release v$VERSION"
git tag -a "v$VERSION" -m "JenderalCode Mobile $VERSION"
git push origin HEAD --tags
gh release create "v$VERSION" --repo "$REPO" --title "JenderalCode Mobile $VERSION" --latest \
  --notes-file "$NOTES" \
  "$OUT/JenderalCode-Mobile-$VERSION.apk" "$OUT/JenderalCode-Mobile.apk" "$OUT/SHA256SUMS"
rm -rf "$OUT"
echo "published https://github.com/$REPO/releases/tag/v$VERSION"
