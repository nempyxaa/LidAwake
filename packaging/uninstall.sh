#!/bin/bash
# LidAwake uninstaller. Safe to run from ANY state — a clean Quit, a crash,
# a force-quit, or a half-broken install.
#
# Order matters: a crash or force-quit can strand SleepDisabled=1
# system-wide (a Mac that never sleeps, with no visible cause), so normal
# sleep is restored — and VERIFIED restored — before anything else. Only
# that gate is allowed to stop the script; every later step is
# best-effort. The watchdog is booted out before the app is deleted so
# KeepAlive cannot respawn-loop on a missing binary.
set -u

# Root-safe: if invoked via `sudo`, re-run as the invoking user. As root,
# `gui/$(id -u)` points at launchd domain gui/0 and $HOME at /var/root, so
# the bootout, guard-plist removal, ~/.lidawake cleanup, and `defaults`
# deletes would all miss the real account — leaving a KeepAlive plist that
# respawn-loops on the deleted app at next login. The invoking user's sudo
# timestamp is already cached, so the pmset step below won't re-prompt.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  exec sudo -u "$SUDO_USER" -H bash "$0" "$@"
fi

echo "Restoring normal sleep (needs your password once)…"

# J-02 gate: teardown may only begin after the restore command exits 0 AND
# a readback confirms SleepDisabled=0. A failed or unverified restore must
# not delete the app and its sudoers rule — they are the two convenient
# recovery paths — and must not print a success message.
restore_failed() {
  echo "" >&2
  echo "ERROR: could not verify that normal sleep was restored." >&2
  echo "Nothing was removed. Restore sleep manually with:" >&2
  echo "" >&2
  echo "  sudo pmset -a disablesleep 0" >&2
  echo "" >&2
  echo "then re-run this uninstaller." >&2
  exit 1
}
sudo pmset -a disablesleep 0 || restore_failed
readback="$(pmset -g 2>/dev/null | awk '/SleepDisabled/ {print $NF}')"
[ "$readback" = "0" ] || restore_failed

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
