#!/bin/bash
# Builds the unsigned Lid Awake installer package into the repo root.
# Usage: packaging/build-pkg.sh [version]
# Payload: /Applications/LidAwake.app (no spaces in any filename; Finder
# shows "Lid Awake" via CFBundleDisplayName).
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-3.0.0}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

./native/build.sh

mkdir -p "$BUILD/root/Applications"
cp -R native/build/LidAwake.app "$BUILD/root/Applications/LidAwake.app"

mkdir -p "$BUILD/scripts"
cp packaging/postinstall "$BUILD/scripts/postinstall"
chmod 755 "$BUILD/scripts/postinstall"

pkgbuild --root "$BUILD/root" --scripts "$BUILD/scripts" \
  --identifier com.nempyxaa.lid-awake.pkg --version "$VERSION" \
  --install-location / "$BUILD/lid-awake-component.pkg"
productbuild --package "$BUILD/lid-awake-component.pkg" "lid-awake-$VERSION.pkg"
echo "Built lid-awake-$VERSION.pkg"
