# Native build

`build.sh` compiles `lid-awake.app` for arm64 and x86_64, merges the binaries with `lipo`, ad-hoc signs the bundle, and runs the state-machine tests. It requires the macOS Command Line Tools and does not launch or install the result.

```sh
./native/build.sh
```

Output: `native/build/lid-awake.app`

The app targets macOS 13 or newer. It runs only in the menu bar (`LSUIElement=1`), registers itself as a login item through `SMAppService`, and replaces the old 60-second LaunchAgent with an internal timer.

The only privileged dependency is the existing sudoers rule:

```text
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset
```

Use `sudo visudo -f /etc/sudoers.d/lid-awake` to add it. The app detects a missing rule and presents the user-specific line in a dialog with a copy button.

Notarization is deferred until the Apple Developer Program fee is paid.
