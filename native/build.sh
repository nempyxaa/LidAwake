#!/bin/bash
# Builds the universal, ad-hoc signed LidAwake.app and runs the tests.
# No spaces in any filename: the bundle is LidAwake.app, and Finder shows
# "LidAwake" via CFBundleDisplayName.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native"
OUT="$NATIVE/build"
APP="$OUT/LidAwake.app"

cd "$NATIVE"
swift test
# Per-arch builds + lipo: works with the Command Line Tools alone
# (the combined --arch invocation needs full Xcode's xcbuild).
for TRIPLE in arm64-apple-macosx14.4 x86_64-apple-macosx14.4; do
  swift build -c release --triple "$TRIPLE"
done
BIN_ARM="$(swift build -c release --triple arm64-apple-macosx14.4 --show-bin-path)/LidAwake"
BIN_X86="$(swift build -c release --triple x86_64-apple-macosx14.4 --show-bin-path)/LidAwake"
RESOURCES="$(dirname "$BIN_ARM")/LidAwake_LidAwake.bundle"

rm -rf "$APP" "$OUT/lid-awake.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$NATIVE/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM emits LidAwake_LidAwake.bundle only when Package.swift declares
# resources for the LidAwake target; since the v3.1 squash dropped the draft
# localizations there is none on a clean build. Copy it only if present, so
# clean checkouts (CI) don't fail on a bundle that a stale .build/ still has.
if [ -d "$RESOURCES" ]; then
  cp -R "$RESOURCES" "$APP/Contents/Resources/"
fi
xcrun lipo -create "$BIN_ARM" "$BIN_X86" -output "$APP/Contents/MacOS/LidAwake"

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
