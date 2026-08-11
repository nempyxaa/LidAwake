# Native build

Run `./native/build.sh` from the repository root. It creates the universal, ad-hoc signed app at `native/build/lid-awake.app` and runs the headless tests. The script does not install or launch the result.

Move the finished app to `/Applications` before opening it. The app will not register its login item or 60-second safety LaunchAgent from `native/build` or another unstable path.

See the repository [README](../README.md) for installation, the restricted sudoers rule, migration behavior, and uninstall steps.
