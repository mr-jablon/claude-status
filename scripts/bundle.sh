#!/bin/bash
# Builds build/ClaudeStatus.app (release, ad-hoc signed).
#   --install  also copy it to ~/Applications and launch it from there
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudeStatus.app"

swift build -c release --package-path "$ROOT" --product ClaudeStatus
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ClaudeStatus" "$APP/Contents/MacOS/ClaudeStatus"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x ClaudeStatus || true
    rm -rf "$DEST/ClaudeStatus.app"
    cp -R "$APP" "$DEST/"
    open "$DEST/ClaudeStatus.app"
    echo "Installed to $DEST/ClaudeStatus.app"
fi
