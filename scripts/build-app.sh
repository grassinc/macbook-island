#!/bin/bash
# Assemble Pill.app from the SwiftPM build product.
#
# TCC identity note: macOS keys Accessibility/Desktop consent to the code
# signature + path. Both are held stable here on purpose — a changing
# identifier or output path makes the user re-approve after every build and
# leaves dead entries in System Settings > Accessibility.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
APP="build/Pill.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Pill"
[ -x "$BIN" ] || { echo "build produced no executable at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc signing (stable identifier)"
codesign --force --sign - --identifier com.pill.app --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo "==> built $APP"
