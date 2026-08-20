#!/bin/bash
# Builds the unsigned LidAwake installer package into the repo root.
# Usage: packaging/build-pkg.sh [version]
# Payload: /Applications/LidAwake.app — "LidAwake" everywhere, no spaces in
# any filename; lowercase identifiers use "lidawake" with no hyphen.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-3.2.0}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

./native/build.sh

# Version single-sourcing: the pkg version and the payload's Info.plist must
# agree, or a 3.1.0 build could ship a 3.0.0 app. Refuse on mismatch (the
# plist is stamped at build time and codesigned; rewriting it here would
# invalidate the signature).
PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw native/build/LidAwake.app/Contents/Info.plist)"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "ERROR: version mismatch — packaging $VERSION but the app's Info.plist says $PLIST_VERSION." >&2
  echo "Update CFBundleShortVersionString and CFBundleVersion in native/Info.plist, then rebuild." >&2
  exit 1
fi

mkdir -p "$BUILD/root/Applications"
cp -R native/build/LidAwake.app "$BUILD/root/Applications/LidAwake.app"

mkdir -p "$BUILD/scripts"
cp packaging/postinstall "$BUILD/scripts/postinstall"
chmod 755 "$BUILD/scripts/postinstall"

# Component plist with relocation OFF. Without it pkgbuild defaults to
# BundleIsRelocatable=true and Installer will "upgrade" any stray
# app.lidawake bundle it finds (a dev-machine build directory, a copy in
# ~/Downloads) instead of installing to /Applications — postinstall then
# opens a path that was never created and the watchdog refuses to install:
# a silent dead install.
pkgbuild --analyze --root "$BUILD/root" "$BUILD/component.plist"
plutil -replace '0.BundleIsRelocatable' -bool NO "$BUILD/component.plist"
[ "$(plutil -extract '0.BundleIsRelocatable' raw "$BUILD/component.plist")" = "false" ]

pkgbuild --root "$BUILD/root" --component-plist "$BUILD/component.plist" \
  --scripts "$BUILD/scripts" \
  --identifier app.lidawake.pkg --version "$VERSION" \
  --install-location / "$BUILD/lidawake-component.pkg"

# Distribution: give the Installer window the proper name (naming law:
# "LidAwake", never the raw filename) and gate on macOS >= 14.4 so an
# older system cannot complete an install of an app that refuses to launch.
productbuild --synthesize --package "$BUILD/lidawake-component.pkg" "$BUILD/distribution.xml"
sed -i '' 's|<installer-gui-script minSpecVersion="[0-9.]*">|&<title>LidAwake</title><allowed-os-versions><os-version min="14.4"/></allowed-os-versions>|' "$BUILD/distribution.xml"
grep -q '<title>LidAwake</title>' "$BUILD/distribution.xml"
grep -q '<os-version min="14.4"/>' "$BUILD/distribution.xml"

productbuild --distribution "$BUILD/distribution.xml" --package-path "$BUILD" "lidawake-$VERSION.pkg"
echo "Built lidawake-$VERSION.pkg"
shasum -a 256 "lidawake-$VERSION.pkg"
