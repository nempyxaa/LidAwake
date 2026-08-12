#!/bin/bash
# Builds the unsigned LidAwake installer package into the repo root.
# Usage: packaging/build-pkg.sh [version]
# Payload: /Applications/LidAwake.app — "LidAwake" everywhere, no spaces in
# any filename; lowercase identifiers use "lidawake" with no hyphen.
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
  --identifier app.lidawake.pkg --version "$VERSION" \
  --install-location / "$BUILD/lidawake-component.pkg"
productbuild --package "$BUILD/lidawake-component.pkg" "lidawake-$VERSION.pkg"
echo "Built lidawake-$VERSION.pkg"
