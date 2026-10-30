#!/usr/bin/env bash
# Builds FileManagerApp with Xcode's toolchain and wraps it in build/File Manager.app.
# Usage: scripts/bundle.sh [debug|release]
# Apple Silicon only: macOS 27 doesn't run on Intel Macs.
# APP_VERSION overrides the version in Resources/Info.plist (the release workflow sets it from
# the git tag).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/File Manager.app"

xcrun swift build -c "$CONFIG"
BIN="$(xcrun swift build -c "$CONFIG" --show-bin-path)/FileManagerApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FileManagerApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The build number is the commit count, so each committed build is higher than the last.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Help > File Manager Help opens these.
cp -R docs "$APP/Contents/Resources/docs"

# Folder access prompts (Desktop, Documents, Downloads) are tied to the code signature. With an
# Apple developer identity macOS remembers them across rebuilds; ad-hoc signing ("-") asks again.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" --options runtime "$APP"
echo "Built $APP (signed: $IDENTITY)"
