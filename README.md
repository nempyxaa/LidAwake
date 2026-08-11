# lid-awake

lid-awake is a native macOS menu-bar app that lets a MacBook keep working with its lid closed. On AC power it enables keep-awake automatically. On battery, you can make the override end when the lid opens, keep it through lid cycles until the battery floor or overheating, or choose the contract each time you turn it on. Plugging in power and manual shutoff always clear a battery override.

The app supports macOS 13 and newer. Its menu and notices follow the Mac's language in English, German, French, Spanish, or Russian.

## Build

```sh
./native/build.sh
```

The build produces `native/build/lid-awake.app`, compiles and asserts both `arm64` and `x86_64`, applies an ad-hoc signature, verifies the bundle, and runs headless state-machine tests. It does not install or launch anything.

## Install

1. Build the app.
2. Move `native/build/lid-awake.app` to `/Applications`.
3. Add the sudoers rule below with `sudo visudo -f /etc/sudoers.d/lid-awake`.
4. Open `/Applications/lid-awake.app`.

lid-awake refuses to register its login item or safety agent when run from a build or download directory. On first launch from `/Applications`, it installs a small per-user LaunchAgent. Every 60 seconds that agent runs the same binary with `--guard-tick`, so safety cleanup does not depend on the menu app staying alive.

The first native launch also unloads and removes the old `org.lidawake.guard` LaunchAgent and removes `lidawake.10s.sh` from SwiftBar's configured plugin directory. It shows a notice if it finds either legacy file. Only one native menu app can run at a time.

## Permission

The app needs these exact privileged `pmset` commands:

```text
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset sleepnow
```

Replace `yourusername` with your macOS account name. If the rule is missing, the app presents the correct user-specific line with a copy button. Read the rule before installing it: it allows only the five command forms the app uses.

## Safety behavior

- On AC power, keep-awake turns on unless you manually switched it off.
- On battery, you can arm an override only at least 5 percentage points above the chosen floor.
- The override restores normal sleep according to the selected lid contract; low battery, AC connection, serious thermal pressure, and a guard gap longer than 420 seconds always restore it.
- Every restore checks `SleepDisabled=0` before clearing persisted override state or sending an OFF notice. A failed restore keeps the retry state and tries again on the next 60-second tick, including on AC power.
- The menu timer has a small tolerance and an App Nap activity assertion for UI freshness. The external LaunchAgent remains the safety authority.

The default battery floor is 20%. You can choose 10, 15, 20, 25, or 30%, select the standing battery contract, disable thermal auto-sleep, and mute notices from Settings.

Thermal events are appended to `~/.lid-awake/state/thermal-history.txt`. Guard diagnostics go to `~/.lid-awake/state/lid-guard.log`.

## Quit and uninstall

Use **Quit** in the lid-awake menu first. It verifies that normal sleep is restored, disables Low Power Mode, unloads and removes the native safety LaunchAgent, unregisters the login item, and then exits. If sleep restoration fails, the app stays open and shows the permission fix.

After a successful Quit:

```sh
rm -rf /Applications/lid-awake.app ~/.lid-awake
defaults delete com.nempyxaa.lid-awake 2>/dev/null || true
sudo rm /etc/sudoers.d/lid-awake
```

The current source build is ad-hoc signed. Developer ID signing and notarization are still release work.

## License

MIT
