#!/bin/bash
# Builds the unsigned lid-awake installer package into the repo root.
# Usage: packaging/build-pkg.sh [version]
# The version defaults to CFBundleShortVersionString from native/Info.plist
# so the package can never claim a different version than the app it carries.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw native/Info.plist)}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

./native/build.sh

mkdir -p "$BUILD/root/Applications"
cp -R native/build/lid-awake.app "$BUILD/root/Applications/"

mkdir -p "$BUILD/scripts"
cp packaging/postinstall "$BUILD/scripts/postinstall"
chmod 755 "$BUILD/scripts/postinstall"

# Pin the bundle as non-relocatable, or Installer may "upgrade" a copy it
# finds elsewhere (e.g. native/build) instead of installing to /Applications.
pkgbuild --analyze --root "$BUILD/root" "$BUILD/component.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/component.plist"

pkgbuild --root "$BUILD/root" --component-plist "$BUILD/component.plist" \
  --scripts "$BUILD/scripts" \
  --identifier org.lidawake.pkg --version "$VERSION" \
  --install-location / "$BUILD/lid-awake-component.pkg"
productbuild --package "$BUILD/lid-awake-component.pkg" "lid-awake-$VERSION.pkg"
echo "Built lid-awake-$VERSION.pkg"
