#!/bin/bash
# lid-awake installer. Requires SwiftBar (https://swiftbar.app).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.lid-awake"

PLUGDIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
if [ -z "$PLUGDIR" ]; then
  echo "SwiftBar not configured. Install SwiftBar, pick a plugin folder, then re-run."
  exit 1
fi

mkdir -p "$DEST/state"
cp "$DIR/lid-toggle.sh" "$DIR/lid-battery-guard.sh" "$DIR/lid-settings.sh" "$DIR/thermalstate" "$DEST/"
chmod +x "$DEST/lid-toggle.sh" "$DEST/lid-battery-guard.sh" "$DEST/lid-settings.sh" "$DEST/thermalstate"
# strip macOS download-quarantine so the thermal helper can run, then verify it does
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
TS=$("$DEST/thermalstate" 2>/dev/null || true)
case "$TS" in
  0|1|2|3) echo "Thermal helper OK (thermalState=$TS)." ;;
  *) echo "WARNING: the thermal helper did not run (Gatekeeper may be blocking it). Thermal auto-sleep will stay INACTIVE until this is resolved; the rest of lid-awake works normally." ;;
esac
cp "$DIR/lidawake.10s.sh" "$PLUGDIR/"
chmod +x "$PLUGDIR/lidawake.10s.sh"

mkdir -p "$HOME/Library/LaunchAgents"
PLIST="$HOME/Library/LaunchAgents/org.lidawake.guard.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>org.lidawake.guard</string>
  <key>ProgramArguments</key><array><string>$DEST/lid-battery-guard.sh</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
if ! sudo -n pmset -g >/dev/null 2>&1; then
  echo "NOTE: passwordless pmset is not set up yet. Add the sudoers line below FIRST, then re-run this installer so the guard can actually control sleep."
fi
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "Installed. One manual step remains: passwordless pmset for the toggle."
echo "Run:  sudo visudo -f /etc/sudoers.d/lid-awake"
echo "and add the single line:"
echo ""
echo "  $USER ALL=(root) NOPASSWD: /usr/bin/pmset"
echo ""
echo "Then click the moon icon in the menu bar. Done."
