# lid-awake

Keep your MacBook running with the lid closed, and never worry that you left it on.

By default, closing the lid sleeps your Mac, exactly like normal. When you actually want it to keep working with the lid shut, you turn that on with one click in the menu bar.

The whole point is what happens after: it turns itself back off. Unplug it, open the lid, drop under 20% battery, or let it start overheating on battery, and it goes back to sleeping normally on its own. You never have to remember you left it awake.

Most keep-awake apps just flip a switch and leave the rest to you. That is how a laptop ends up hot and draining in a bag. This one puts it back the way it found it.

## What it does

- **Closed lid, on power:** keeps running. Turns on by itself when you plug in.
- **Closed lid, on battery:** stays asleep by default. One click keeps it awake for a while, and also switches on Low Power Mode so a closed laptop stays cool.
- **Any override ends on its own:** open the lid, unplug, go under 20%, or start overheating, and it reverts.
- **Won't arm under 25% battery.** Won't cook itself: if the Mac throttles from heat on battery, it sleeps and leaves you a plain dated note.

Menu and alerts are in your Mac's language (English or Russian). You can mute the alerts from the menu. Native menu-bar icons, about 200 lines of bash, MIT.


Every exception lives exactly one lid cycle. The battery override reverts itself when you open the lid, when battery drops below 20%, or when power state changes — and Low Power Mode is restored on every exit path. Refuses to arm below 25%. All markers die on reboot.

Menu and notifications are localized from the OS language (English, Russian; English fallback). Notifications can be muted from the menu (🔔/🔕) - the state machine keeps working silently.



## Overheating protection

While it keeps a closed laptop awake on battery, the guard watches whether macOS is throttling for heat (it reads `pmset -g therm` every 60 seconds). If your Mac starts to overheat, it puts it to sleep so it can cool, and leaves you a plain note like:

> Went to sleep due to overheating at 2:35pm on Saturday, 15 Aug

The note shows up in Notification Center, so you see exactly what happened and when. There's also a one-line text history at `~/.lid-awake/thermal-history.txt` if you want to look back.

## Adjustable, on by default

Both safety limits are on out of the box and adjustable from the menu:
- **Thermal auto-sleep** (thermometer icon) — on/off.
- **Battery floor** (battery icon) — click to cycle 25 / 20 / 15 / 10%. The Mac won't arm an override 5% above the floor, and drops the override at the floor.

## Battery floors

- **Refuses to arm below 25%.**
- **Revokes an active override below 20%** and lets the Mac sleep.

## Install

1. Install [SwiftBar](https://swiftbar.app) and pick a plugin folder.
2. `./install.sh`
3. One manual step (the installer prints it): allow passwordless `pmset` via `sudo visudo -f /etc/sudoers.d/lid-awake` with the line
   `yourusername ALL=(root) NOPASSWD: /usr/bin/pmset`

That sudoers line is the only privilege the tool needs: `pmset` toggles `disablesleep` and `lowpowermode`. All scripts are ~200 lines of plain bash — read them.

## Uninstall

```
launchctl unload ~/Library/LaunchAgents/org.lidgovernor.guard.plist
rm -rf ~/.lid-awake ~/Library/LaunchAgents/org.lidgovernor.guard.plist
rm <your SwiftBar plugin folder>/lid.10s.sh
sudo rm /etc/sudoers.d/lid-awake
sudo pmset -a disablesleep 0
```

## License

MIT
