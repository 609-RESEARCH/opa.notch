#!/bin/bash
# Builds a Release opa.notch.app and packages it as dist/opa.notch.dmg
# (drag-to-Applications disk image) plus a SHA-256 checksum.
#
# Usage: scripts/build-release.sh
#
# Signing: uses the project's signing settings. Without a Developer ID certificate the
# app is ad-hoc signed and not notarized, so macOS asks people to approve it on first
# launch (System Settings → Privacy & Security → Open Anyway).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="opa.notch"
# Build outside the source folder: synced folders such as iCloud Drive add extended
# attributes that codesign rejects ("resource fork, Finder information … not allowed").
BUILD="${OPA_BUILD_DIR:-$HOME/Library/Caches/opa.notch-release}"

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

echo "› Building Release (Apple Silicon + Intel)…"
if ! xcodebuild \
    -project "$ROOT/OpaNotch.xcodeproj" \
    -scheme OpaNotch \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD/derived" \
    build > "$BUILD/build.log" 2>&1; then
    grep -E "error:|failed" "$BUILD/build.log" >&2 || true
    echo "Build failed; full log: $BUILD/build.log" >&2
    exit 1
fi

APP="$BUILD/derived/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$APP"
echo "› Signed: $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|Authority)=' | head -1)"
echo "› Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "› Packaging $APP_NAME $VERSION…"

STAGING="$BUILD/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# A stable file name keeps the README's "latest release" download link valid.
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DIST/$APP_NAME.dmg" >/dev/null

(cd "$DIST" && shasum -a 256 "$APP_NAME.dmg" > "$APP_NAME.dmg.sha256")

echo "› Done: dist/$APP_NAME.dmg ($VERSION)"
cat "$DIST/$APP_NAME.dmg.sha256"
