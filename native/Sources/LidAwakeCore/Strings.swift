import Foundation

// Canonical v3 strings ("Exit Signs" spec, 2026-08-12). "Keep awake" — capital
// K, lowercase a — is the feature's proper name in every user-facing string.
// Percentages render live from the Battery floor setting.

public enum V3Strings {
    public static let appName = "LidAwake"
    /// Status-item title when no icon image could be produced — the status
    /// item must never sit imageless AND titleless (the v2 regression).
    public static let iconFallback = "LA"

    // MARK: Headers (disabled lines; the battery line is always last)
    public static let idleHeader = "Lid closed: sleeps"
    public static let oneShotHeader = "Lid closed: Keep awake"
    public static let alwaysHeader = "Lid closed: every time Keep awake"
    public static let acHeaderOn = "Lid closed: Keep awake (on power)"
    public static let acHeaderDeclined = "Lid closed: sleeps (on power)"
    public static let acHoldHeader = "On power: Keep awake resumes on battery"

    public static func battery(_ percent: Int?) -> String {
        "Battery: \(percent.map(String.init) ?? "?")%"
    }
    public static func batteryCharging(_ percent: Int?) -> String {
        "Battery: \(percent.map(String.init) ?? "?")%, charging"
    }
    public static func untilOneShotLid(_ floor: Int) -> String {
        "Until: lid opens, \(floor)%, or hot"
    }
    public static func untilOneShotIgnoringLid(_ floor: Int) -> String {
        "Until: \(floor)% or hot — ignores lid"
    }
    public static func alwaysUntil(_ floor: Int) -> String {
        "Until \(floor)% or hot, always"
    }
    public static func pausedFloor(_ floor: Int) -> String {
        "Keep awake resumes at \(floor + StateMachine.resumeMargin)%"
    }
    public static let pausedHot = "Paused: cooling down"
    public static func postmortem(_ percent: Int, _ time: String) -> String {
        "Last Keep awake: ended at \(percent)%, \(time)"
    }

    // MARK: Menu items
    public static let armItem = "Keep awake with lid closed"
    public static func armSubUntilLid(_ floor: Int) -> String {
        "Until lid opens, \(floor)%, or hot"
    }
    public static func armSubIgnoringLid(_ floor: Int) -> String {
        "Ignoring lid, until \(floor)% or hot"
    }
    public static let armSubChangeMode = "Change mode in Settings"
    public static let armSubOnPower = "On power: Keep awake automatically"
    public static func armDisabledLow(_ floor: Int) -> String {
        // D7: floorHit is <=, so "below" would be false at exactly N%.
        "Battery at or below \(floor)%"
    }
    public static let armDisabledHot = "Cooling down"
    public static let turnOff = "Turn off Keep awake"
    /// Subtitle on the moon item in the on-power idle menu (D2): the decline
    /// is standing on power, so the item says so.
    public static let turnOffOnPowerSub = "Stays off on power until you turn it back on"
    public static let sleepNow = "Sleep now"
    public static let sleepNowSubOneShot = "Sleeps and turns Keep awake off"
    public static let skipOnceItem = "Sleep on next lid close"
    public static let skipOnceSub = "Always Keep awake stays on"
    public static let skipOnceArmedItem = "Cancel one-time sleep"
    public static let turnOffAlwaysItem = "Turn off Always Keep awake"
    public static let turnOffAlwaysSub = "Keep awake only when you click it"
    public static let settings = "Settings"

    // MARK: Settings
    public static let showNotifications = "Show notifications"
    public static func floorItem(_ floor: Int) -> String { "Battery floor: \(floor)%" }
    public static func floorOption(_ value: Int) -> String { "\(value)%" }
    public static func floorOptionEndsCurrent(_ value: Int) -> String {
        "\(value)% — ends current Keep awake"
    }
    public static let modeSection = "On battery, Keep awake"
    public static func modeRadioUntilLid(_ floor: Int) -> String {
        "When turned on: until lid opens, \(floor)%, or hot"
    }
    public static func modeRadioIgnoringLid(_ floor: Int) -> String {
        "When turned on: ignoring lid, until \(floor)% or hot"
    }
    public static func modeRadioAlways(_ floor: Int) -> String {
        "Always when on battery: until \(floor)% or hot"
    }
    public static let about = "About LidAwake"
    public static let quit = "Quit LidAwake"
    public static let quitConfirm = "Quitting turns off Keep awake; next lid close sleeps."

    // MARK: Notifications
    public static let notifyACOn = "On power: keeping the Mac awake automatically. Click the moon to turn off."
    public static let notifyBatteryOff = "On battery: Keep awake off, the lid sleeps the Mac as usual."
    public static let notifyManualOff = "Keep awake off."
    public static let notifyLidEnd = "Lid opened: Keep awake ended."
    public static func notifyFloorEnd(_ percent: Int) -> String {
        "Keep awake ended: battery at \(percent)%."
    }
    public static let notifyHotEnd = "Keep awake ended: cooling down."
    public static func notifyFloorPaused(_ floor: Int) -> String {
        "Keep awake paused: resumes at \(floor + StateMachine.resumeMargin)%."
    }
    public static let notifyHotPaused = "Keep awake paused: cooling down."
    public static let notifyAlwaysResumed = "Keep awake resumed."
    public static let notifyACExpired = "Keep awake ended: 30 minutes on power."
    public static let notifyOverheatInvariant = "Overheat protection is now always on"
    public static let notifyFailure = "Could not turn on Keep awake: pmset needs the passwordless sudo rule (see README). Nothing changed."
    public static let notifyRevertFailure = "Could not restore normal sleep. LidAwake will retry in 60 seconds."

    /// Every canonical string, rendered for a given floor — used by the tests
    /// to enforce the proper-name rule mechanically.
    public static func allStrings(floor: Int) -> [String] {
        [appName, iconFallback, idleHeader, oneShotHeader, alwaysHeader, acHeaderOn, acHeaderDeclined,
         acHoldHeader, battery(40), batteryCharging(78),
         untilOneShotLid(floor), untilOneShotIgnoringLid(floor), alwaysUntil(floor),
         pausedFloor(floor), pausedHot, postmortem(18, "14:05"),
         armItem, armSubUntilLid(floor), armSubIgnoringLid(floor), armSubChangeMode,
         armSubOnPower, armDisabledLow(floor), armDisabledHot,
         turnOff, turnOffOnPowerSub, sleepNow, sleepNowSubOneShot,
         skipOnceItem, skipOnceSub, skipOnceArmedItem,
         turnOffAlwaysItem, turnOffAlwaysSub, settings,
         showNotifications, floorItem(floor), floorOption(floor), floorOptionEndsCurrent(floor),
         modeSection, modeRadioUntilLid(floor), modeRadioIgnoringLid(floor), modeRadioAlways(floor),
         about, quit, quitConfirm,
         notifyACOn, notifyBatteryOff, notifyManualOff, notifyLidEnd,
         notifyFloorEnd(floor), notifyHotEnd, notifyFloorPaused(floor), notifyHotPaused,
         notifyAlwaysResumed, notifyACExpired, notifyOverheatInvariant,
         notifyFailure, notifyRevertFailure]
    }
}
