# Lid Awake

Lid Awake is a native macOS menu-bar app that lets a MacBook keep working with
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
in [docs/states.md](docs/states.md).

## Build

```sh
./native/build.sh
```

The script runs `swift test` and a universal release `swift build` in
`native/`, then produces the ad-hoc signed bundle at
`native/build/LidAwake.app` and verifies both `arm64` and `x86_64`. It does
not install or launch anything.

## Install

1. Build the app.
2. Move `native/build/LidAwake.app` to `/Applications`.
3. Add the sudoers rule below with `sudo visudo -f /etc/sudoers.d/lid-awake`.
4. Open `/Applications/LidAwake.app`.

Alternatively, `packaging/build-pkg.sh` builds an installer package that does
steps 2–4, deletes an old `lid-awake.app` from a v2 install, and installs the
restricted sudoers rule for admin users.

On first launch from `/Applications` the app installs its watchdog: a
per-user KeepAlive LaunchAgent (`com.nempyxaa.lid-awake.guard`) that starts
the app at login and relaunches it after a crash. Every launch reconciles
`pmset` to the stored policy, deletes a leftover v2 `lid-awake.app` bundle,
and sweeps v1 remnants by enumeration (agents, SwiftBar plugins, scripts —
each removed file is first backed up under `~/.lid-awake/backups/`). Only one
instance runs at a time.

macOS 14.4 or newer.

## Permission

The app needs these exact privileged `pmset` commands:

```text
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset sleepnow
```

Replace `yourusername` with your macOS account name. If the rule is missing,
the app presents the correct user-specific line with a copy button. Read the
rule before installing it: it allows only the five command forms the app uses.

## Safety behavior

- The floor and heat always end Keep awake, in every mode. The forced sleep
  runs only while the lid is closed; with the lid open the app disarms,
  restores the default `pmset`, and notifies.
- Plugging in never causes a sleep by itself. A one-shot held on power expires
  after 30 minutes — except when automatic Keep awake is declined and the lid
  is closed, where it survives until unplug. Unplugging re-checks the floor.
- Arming needs battery at floor + 5% and five minutes of nominal thermals —
  the same predicate that resumes the Always mode.
- Every `pmset` restore is verified before policy state is cleared; a failed
  write keeps the stored policy and the next tick retries.
- Ends you did not cause (floor, heat, expiry, restart) leave a menu line:
  `Last Keep awake: ended at N%, HH:MM`.

Thermal events append to `~/.lid-awake/state/thermal-history.txt`; guard
diagnostics go to `~/.lid-awake/state/lid-guard.log`.

## Quit and uninstall

Use **Quit Lid Awake** in Settings first. It always reverts `pmset`, and asks
one line — `Quitting turns off Keep awake; next lid close sleeps.` — when
anything is active. It unloads and removes the watchdog LaunchAgent before
exiting.

After a successful Quit:

```sh
rm -rf /Applications/LidAwake.app /Applications/lid-awake.app ~/.lid-awake
defaults delete com.nempyxaa.lid-awake 2>/dev/null || true
sudo rm /etc/sudoers.d/lid-awake
```

The `/Applications/lid-awake.app` entry only exists on machines upgraded from
v2; the app deletes it itself on first v3 launch.

The current source build is ad-hoc signed. Developer ID signing and
notarization are still release work.

## Naming

"Lid Awake" in prose; `lid-awake` only in code spans, paths, and identifiers
(the repo, the bundle identifier `com.nempyxaa.lid-awake`, the brew cask
token). The bundle on disk is `LidAwake.app` — no spaces in filenames. CI
(`scripts/check-naming.sh`) greps prose for the lowercase name and for the
banned terms; the tests enforce the same rule over every user-facing string.

## License

MIT
