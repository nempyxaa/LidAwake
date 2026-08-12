# Native build

Run `./native/build.sh` from the repository root. It runs `swift test`, builds
the universal release binary with SwiftPM, and creates the ad-hoc signed app
at `native/build/LidAwake.app`. The script does not install or launch the
result.

`swift build` and `swift test` also work directly in `native/`.

Move the finished app to `/Applications` before opening it. The app will not
install its watchdog LaunchAgent from `native/build` or another unstable path.

See the repository [README](../README.md) for installation, the restricted
sudoers rule, migration behavior, and uninstall steps, and
[docs/states.md](../docs/states.md) for the full state machine.
