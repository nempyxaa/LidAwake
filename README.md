# lid-governor

A tiny SwiftBar menu-bar manager for what your MacBook does when you close the lid — with a battery-safe override and minimal heat.

Most keep-awake tools (Amphetamine, caffeinate) leave it to you to remember state. lid-governor is a governor: it has defaults, one-click exceptions, and every exception dies on its own.

## What it does

| State | Icon | Behavior |
|---|---|---|
| Default | moon.zzz | Closing the lid sleeps the Mac, as macOS intends |
| Night mode (AC) | moon.fill | On power, the Mac keeps working with the lid closed. Auto-enables when you plug in; one click to decline for the session |
| Battery override | moon.circle.fill | Temporary keep-awake on battery, and it enables macOS Low Power Mode so the closed laptop runs as cool as possible |

Every exception lives exactly one lid cycle. The battery override reverts itself when you open the lid, when battery drops below 20%, or when power state changes — and Low Power Mode is restored on every exit path. Refuses to arm below 25%. All markers die on reboot.

Menu and notifications are localized from the OS language (English, Russian; English fallback). Notifications can be muted from the menu (🔔/🔕) - the state machine keeps working silently.



## Thermal safety + learning log

While it keeps a closed laptop awake on battery, the guard reads `pmset -g therm` every 60s. macOS drops `CPU_Speed_Limit` below 100 the moment it throttles for heat or power. If that happens, the guard forces the Mac to sleep so it cools — you cannot cook a machine in a bag.

Every tick is recorded to `~/.lid-governor/state/thermal-events.csv` (`iso_time,battery_pct,cpu_speed_limit,action`) while an override is active, with a `forced-sleep` row whenever it acts. It is a plain CSV you can open, chart, or share — a record of how your own Mac behaves thermally with the lid shut.

## Battery floors

- **Refuses to arm below 25%.**
- **Revokes an active override below 20%** and lets the Mac sleep.

## Install

1. Install [SwiftBar](https://swiftbar.app) and pick a plugin folder.
2. `./install.sh`
3. One manual step (the installer prints it): allow passwordless `pmset` via `sudo visudo -f /etc/sudoers.d/lid-governor` with the line
   `yourusername ALL=(root) NOPASSWD: /usr/bin/pmset`

That sudoers line is the only privilege the tool needs: `pmset` toggles `disablesleep` and `lowpowermode`. All scripts are ~200 lines of plain bash — read them.

## Uninstall

```
launchctl unload ~/Library/LaunchAgents/org.lidgovernor.guard.plist
rm -rf ~/.lid-governor ~/Library/LaunchAgents/org.lidgovernor.guard.plist
rm <your SwiftBar plugin folder>/lid.10s.sh
sudo rm /etc/sudoers.d/lid-governor
sudo pmset -a disablesleep 0
```

## License

MIT
