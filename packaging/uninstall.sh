#!/bin/bash
# LidAwake uninstaller. Safe to run from ANY state — a clean Quit, a crash,
# a force-quit, or a half-broken install. Every step is best-effort; the
# one that matters most runs first.
#
# Order matters: a crash or force-quit can strand SleepDisabled=1
# system-wide (a Mac that never sleeps, with no visible cause), so normal
# sleep is restored before anything else. The watchdog is booted out before
# the app is deleted so KeepAlive cannot respawn-loop on a missing binary.
set -u

echo "Restoring normal sleep (needs your password once)…"
sudo pmset -a disablesleep 0

# Watchdog first: bootout the guard job, then remove its plist.
launchctl bootout "gui/$(id -u)/app.lidawake.guard" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/app.lidawake.guard.plist"

# Stop any running instance (current or v2), then remove the bundles.
pkill -f '/Applications/LidAwake.app/Contents/MacOS/' 2>/dev/null || true
pkill -f '/Applications/lid-awake.app/Contents/MacOS/' 2>/dev/null || true
sudo rm -rf /Applications/LidAwake.app /Applications/lid-awake.app

# State, defaults, sudoers — current and old-form leftovers.
rm -rf "$HOME/.lidawake" "$HOME/.lid-awake"
defaults delete app.lidawake 2>/dev/null || true
defaults delete com.nempyxaa.lid-awake 2>/dev/null || true
sudo rm -f /etc/sudoers.d/lidawake /etc/sudoers.d/lid-awake

# Old-form LaunchAgents from v1/v2 installs that never ran the v3 migration.
for label in com.nempyxaa.lid-awake.guard org.lidawake.guard lv.fleet.lidguard; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done

# Forget the installer receipt so a future pkg installs fresh.
sudo pkgutil --forget app.lidawake.pkg 2>/dev/null || true

echo "LidAwake removed. Normal sleep restored."
