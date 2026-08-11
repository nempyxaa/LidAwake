#!/bin/bash
# Builds the unsigned lid-awake installer package into the repo root.
# Usage: packaging/build-pkg.sh [version]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

ROOT="$BUILD/root/Library/Application Support/lid-awake"
mkdir -p "$ROOT"
cp lid-toggle.sh lid-battery-guard.sh lid-settings.sh lidawake.10s.sh thermalstate lid-awake-setup "$ROOT/"
chmod 755 "$ROOT"/*

mkdir -p "$BUILD/scripts"
cp packaging/postinstall "$BUILD/scripts/postinstall"
chmod 755 "$BUILD/scripts/postinstall"

pkgbuild --root "$BUILD/root" --scripts "$BUILD/scripts" \
  --identifier org.lidawake.pkg --version "$VERSION" \
  --install-location / "$BUILD/lid-awake-component.pkg"
productbuild --package "$BUILD/lid-awake-component.pkg" "lid-awake-$VERSION.pkg"
echo "Built lid-awake-$VERSION.pkg"
