# LidAwake

LidAwake is a native macOS menu-bar app that lets a MacBook keep working with
its lid closed. **Keep awake** is the feature's name: on power the app keeps
the Mac awake automatically (click the moon in the menu to decline); on
battery you choose how Keep awake ends in Settings.

Three battery modes, shown as radios under "On battery, Keep awake":

1. **When turned on: until lid opens, 20%, or hot** — the default. A one-shot:
   you click it, and it ends when you open the lid, hit the battery floor, or
   the Mac runs hot.
2. **When turned on: ignoring lid, until 20% or hot** — a one-shot that
   survives lid opens; only the floor or heat ends it.
3. **Always when on battery: until 20% or hot** — a standing policy: every lid
   close on battery keeps the Mac awake, no click needed. The floor or heat
   pause it; it resumes on its own at floor + 5% once thermals have been
   nominal for five minutes. It survives reboots; one-shots do not.

The percentages render live from the Battery floor setting (10–30%). Overheat
protection is always on: the floor and heat always end Keep awake, and a
forced sleep happens only while the lid is closed — an open, in-use Mac is
never put to sleep.

The full state diagram, transition rules, and an honest limitations list live
in [docs/states.md](docs/states.md). The approved menu mockups are in
[docs/mockups/lidawake-v3-mockups.html](docs/mockups/lidawake-v3-mockups.html);
real screenshots replace them post-build.

## Requirements

- macOS 14.4 or newer (Apple silicon or Intel; the app menu uses
  `NSMenuItem.subtitle`).
- A MacBook. LidAwake is a laptop utility: the battery percentage is a
  safety input to every mode. When no percentage is readable (a desktop
  Mac, or a failed probe on a MacBook), arming is refused and a running
  Keep awake ends, reported as `Battery unavailable` — a distinct
  condition, not a floor hit.
- To build: the Swift 6 toolchain — Xcode 16, or the Command Line Tools 16
  or newer. No full Xcode needed.

## Install

Prebuilt packages will appear on the
[Releases page](https://github.com/nempyxaa/LidAwake/releases) with the
v3.0.0 tag (the older v1 asset there is the retired identity — skip it).
Until then, build from source:

```sh
git clone https://github.com/nempyxaa/LidAwake.git
cd LidAwake
./packaging/build-pkg.sh
sudo installer -pkg lidawake-3.0.0.pkg -target /
```

The pkg puts `LidAwake.app` in `/Applications`, installs the restricted
sudoers rule below for admin users, deletes an old `lid-awake.app` from a v2
install, and opens the app. The build prints the package's SHA-256 —
compare it if the pkg traveled anywhere before installing.

Upgrading from v2? The installer removes the old app and its sudoers file.
If you had added v2's per-user rule by hand, remove the leftover with
`sudo rm -f /etc/sudoers.d/lid-awake`.

To skip the installer:

```sh
./native/build.sh
mv native/build/LidAwake.app /Applications/
sudo visudo -f /etc/sudoers.d/lidawake   # add the rule from Permission below
open /Applications/LidAwake.app
```

`native/build.sh` runs `swift test` and a universal release `swift build` in
`native/`, then produces the ad-hoc signed bundle at
`native/build/LidAwake.app` and verifies both `arm64` and `x86_64`. It does
not install or launch anything.

On first launch from `/Applications` the app installs its watchdog: a
per-user KeepAlive LaunchAgent (`app.lidawake.guard`) that starts the app at
login and relaunches it after a crash. Every launch reconciles `pmset` to the
stored policy, deletes a leftover v2 `lid-awake.app` bundle, migrates state
and defaults from the retired identifiers (`com.nempyxaa.lid-awake`, the
`~/.lid-awake` state dir), and sweeps v1 remnants by enumeration (agents,
SwiftBar plugins, scripts — each removed file is first backed up under
`~/.lidawake/backups/`). Only one instance runs at a time.

## Permission

The app needs these exact privileged `pmset` commands:

```text
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset sleepnow
```

Replace `yourusername` with your macOS account name. If the rule is missing,
the app presents the correct user-specific line with a copy button. Read the
rule before installing it: it allows only the five command forms the app uses.

The `lowpowermode` pair supports the default setting that turns on system Low
Power Mode while Keep awake is active on battery. When Keep awake ends, the
app restores the value you had before it armed. You can turn this setting off;
LidAwake then leaves Low Power Mode untouched.

## Safety behavior

- The floor and heat always end Keep awake, in every mode — on power too.
  The forced sleep runs only while the lid is closed; with the lid open the
  app disarms, restores the default `pmset`, and notifies.
- On power, heat ends a held one-shot and suspends the automatic on-power
  Keep awake until thermals recover; a hot Mac on the charger never holds
  `SleepDisabled`.
- Plugging in never causes a sleep by itself. A one-shot held on power expires
  after 30 minutes — except when automatic Keep awake is declined and the lid
  is closed, where it survives until unplug. Unplugging re-checks the floor.
- Arming a one-shot is disabled only at or below the battery floor, or while
  the Mac is hot — the reason shows as the menu subtitle. The resume
  predicate (battery at floor + 5% and five minutes of nominal thermals)
  governs when the Always mode resumes, including on unplug.
- Every `pmset` restore is verified before policy state is cleared; a failed
  write keeps the stored policy — and the lid/power edge it was reacting
  to — so the next tick retries the same transition.
- Ends you did not cause (floor, heat, expiry, restart) leave a menu line:
  `Last Keep awake: ended at N%, HH:MM`.

Thermal events append to `~/.lidawake/state/thermal-history.txt`; guard
diagnostics go to `~/.lidawake/state/lid-guard.log`.

## Quit and uninstall

Use **Quit LidAwake** in Settings first when you can. It always reverts
`pmset`, and asks one line — `Quitting turns off Keep awake; next lid close
sleeps.` — when anything is active. It unloads and removes the watchdog
LaunchAgent before exiting.

To uninstall, run the script — it is safe from any state, including after a
crash or force-quit. Run it as yourself, without `sudo` — it elevates only
the steps that need it and prompts for your password once. (Run under
`sudo` anyway, it re-executes as your user, so per-user cleanup still lands
in the right account.)

```sh
bash packaging/uninstall.sh
```

Or by hand. **Order matters.** A crash or force-quit can strand
`SleepDisabled=1` system-wide (a Mac that never sleeps, with no visible
cause), so restore normal sleep FIRST; and boot the watchdog out before
deleting the app, or KeepAlive respawn-loops on a missing binary:

```sh
sudo pmset -a disablesleep 0
launchctl bootout "gui/$(id -u)/app.lidawake.guard" 2>/dev/null || true
rm -f ~/Library/LaunchAgents/app.lidawake.guard.plist
sudo rm -rf /Applications/LidAwake.app /Applications/lid-awake.app
rm -rf ~/.lidawake ~/.lid-awake
defaults delete app.lidawake 2>/dev/null || true
defaults delete com.nempyxaa.lid-awake 2>/dev/null || true
sudo rm -f /etc/sudoers.d/lidawake /etc/sudoers.d/lid-awake
sudo pkgutil --forget app.lidawake.pkg 2>/dev/null || true
```

The hyphenated paths, the `com.nempyxaa.lid-awake` domain, and the old-form
LaunchAgents (`com.nempyxaa.lid-awake.guard`, `org.lidawake.guard`,
`lv.fleet.lidguard` — the script removes those too) only exist on machines
upgraded from v2 or an earlier v3 build; the app migrates and removes them
itself on first launch.

The current source build is ad-hoc signed. Developer ID signing and
notarization are still release work.

## Naming

The app is **LidAwake** — CamelCase, one word — on every surface: prose, the
bundle (`CFBundleName`/`CFBundleDisplayName`), menu items ("Quit LidAwake",
"About LidAwake"), and notification titles. Where lowercase is forced it is
`lidawake` with no hyphen: the bundle identifier `app.lidawake`, the brew
cask token `lidawake`, slugs. The spaced and hyphenated old forms are retired
everywhere except historical identifiers that migration must keep
enumerating. CI (`scripts/check-naming.sh`) bans the retired forms and the
banned feature terms in prose; the tests enforce the same rule over every
user-facing string.

## License

MIT
