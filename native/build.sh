#!/bin/bash
# Builds the universal, ad-hoc signed LidAwake.app and runs the tests.
# No spaces in any filename: the bundle is LidAwake.app; Finder shows
# "Lid Awake" via CFBundleDisplayName.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native"
OUT="$NATIVE/build"
APP="$OUT/LidAwake.app"

cd "$NATIVE"
swift test
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LidAwake"

rm -rf "$APP" "$OUT/lid-awake.app"
mkdir -p "$APP/Contents/MacOS"
cp "$NATIVE/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/LidAwake"

codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
ARCHS="$(xcrun lipo -archs "$APP/Contents/MacOS/LidAwake" | tr ' ' '\n' | sort | xargs)"
if [[ "$ARCHS" != "arm64 x86_64" ]]; then
  echo "unexpected executable architectures: $ARCHS" >&2
  exit 1
fi
echo "$ARCHS"
echo "Built $APP"
