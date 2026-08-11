#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native"
OUT="$NATIVE/build"
APP="$OUT/lid-awake.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP" "$OUT/arm64" "$OUT/x86_64"
mkdir -p "$APP/Contents/MacOS" "$OUT/arm64" "$OUT/x86_64"
cp "$NATIVE/Info.plist" "$APP/Contents/Info.plist"

SOURCES=("$NATIVE/Sources/StateMachine.swift" "$NATIVE/Sources/LidAwakeApp.swift")
FRAMEWORKS=(-framework AppKit -framework UserNotifications -framework ServiceManagement)
for ARCH in arm64 x86_64; do
  xcrun swiftc -parse-as-library -O -target "$ARCH-apple-macosx13.0" -sdk "$SDK" \
    -module-cache-path "$OUT/$ARCH/module-cache" \
    "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$OUT/$ARCH/lid-awake"
done
xcrun lipo -create "$OUT/arm64/lid-awake" "$OUT/x86_64/lid-awake" -output "$APP/Contents/MacOS/lid-awake"
codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
ARCHS="$(xcrun lipo -archs "$APP/Contents/MacOS/lid-awake" | tr ' ' '\n' | sort | xargs)"
if [[ "$ARCHS" != "arm64 x86_64" ]]; then
  echo "unexpected executable architectures: $ARCHS" >&2
  exit 1
fi
echo "$ARCHS"

swiftc -module-cache-path "$OUT/test-module-cache" \
  "$NATIVE/Sources/StateMachine.swift" "$NATIVE/Tests/StateMachineTests.swift" -o "$OUT/state-machine-tests"
"$OUT/state-machine-tests"
