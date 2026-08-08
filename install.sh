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
cp "$DIR/lid-toggle.sh" "$DIR/lid-battery-guard.sh" "$DIR/lid-settings.sh" "$DEST/"
chmod +x "$DEST/lid-toggle.sh" "$DEST/lid-battery-guard.sh"
cp "$DIR/lid.10s.sh" "$PLUGDIR/"
chmod +x "$PLUGDIR/lid.10s.sh"

PLIST="$HOME/Library/LaunchAgents/org.lidgovernor.guard.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>org.lidgovernor.guard</string>
  <key>ProgramArguments</key><array><string>$DEST/lid-battery-guard.sh</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
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
