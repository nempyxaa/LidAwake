import AppKit
import LidAwakeCore

// The AppKit half of #4: probing whether the status item is actually
// drawn, and turning IconVisibility's episode events into one user
// notification each way. Checked from the 60-second tick and on screen-
// parameter changes (display added or removed, notch geometry change) —
// both cheap, no new IOKit machinery.

@MainActor
extension AppDelegate {
    /// Whether the status item's button is actually visible on some
    /// screen. AppKit offers no direct "am I overflowed" API; the reliable
    /// observable is the button's hosting window — missing, occluded,
    /// zero-sized, or intersecting no screen all mean the cup is not
    /// drawn, whatever the process believes.
    var statusItemOnScreen: Bool {
        guard let window = status.button?.window else { return false }
        guard window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func checkStatusItemVisibility() {
        guard !headless else { return } // no status item exists to probe
        switch iconVisibility.observe(visible: statusItemOnScreen) {
        case .becameHidden:
            // The armed state rides along in the body: with the menu
            // unreachable, this notification is the only way to trust
            // Keep awake without seeing the cup.
            let s = snapshot()
            let state = s.sleepDisabled ? V3Strings.iconHiddenKeepAwakeOn
                                        : V3Strings.iconHiddenKeepAwakeOff
            appendLog("status item hidden by menu bar overflow (\(state))")
            // The notifications toggle normally gates delivery; a hidden
            // icon is the one case where the notification is the only
            // remaining surface, so it bypasses the toggle.
            deliverNotification(body: V3Strings.notifyIconHidden(state), bypassToggle: true)
        case .becameVisible:
            appendLog("status item visible again")
            deliverNotification(body: V3Strings.notifyIconBack, bypassToggle: true)
        case nil:
            break
        }
    }

    @objc func screenParametersChanged() { checkStatusItemVisibility() }
}
