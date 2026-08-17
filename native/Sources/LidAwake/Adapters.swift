import Darwin
import Foundation
import LidAwakeCore

// J-10: the system boundaries the app writes to and reads from, as
// injectable seams. The executable layer's failure handling — checked
// writes, three-state readbacks, verified restores — is testable only if
// pmset and launchd can fail on demand. Production uses the System
// adapters below; tests inject fakes.

/// The pmset/ioreg power boundary.
protocol PowerAdapting: Sendable {
    /// pmset -a disablesleep write; returns the command's exit status.
    @discardableResult func writeSleepDisabled(_ value: Bool) -> Int32
    /// Three-state SleepDisabled readback (J-06): true / false / nil for
    /// unknown — the command failed or printed something unparseable.
    func readSleepDisabled() -> Bool?
    /// pmset -b lowpowermode write; returns the command's exit status.
    @discardableResult func writeBatteryLowPowerMode(_ value: Int) -> Int32
    /// Battery-scoped lowpowermode from pmset -g custom; nil = unknown.
    func readBatteryLowPowerModeSetting() -> Int?
    /// Live system LPM state, for snapshotting the user's own value.
    func liveLowPowerModeEnabled() -> Bool
    func powerSource() -> PowerSource
    func batteryPercent() -> Int?
    func lidState() -> LidState
    func sleepNow()
}

struct SystemPowerAdapter: PowerAdapting {
    func writeSleepDisabled(_ value: Bool) -> Int32 {
        Shell.pmset(["-a", "disablesleep", value ? "1" : "0"], sudo: true).0
    }
    func readSleepDisabled() -> Bool? {
        let (status, output) = Shell.pmset(["-g"])
        guard status == 0,
              let line = output.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }),
              let flag = line.split(whereSeparator: \.isWhitespace).last else { return nil }
        if flag == "1" { return true }
        if flag == "0" { return false }
        return nil
    }
    func writeBatteryLowPowerMode(_ value: Int) -> Int32 {
        Shell.pmset(["-b", "lowpowermode", String(value)], sudo: true).0
    }
    func readBatteryLowPowerModeSetting() -> Int? {
        // pmset -g custom, because the -b setting is what our writes
        // change; the live ProcessInfo value tracks the ACTIVE power
        // source and cannot verify a -b write made on AC.
        let (status, output) = Shell.pmset(["-g", "custom"])
        guard status == 0 else { return nil }
        var inBatterySection = false
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Battery Power:") { inBatterySection = true; continue }
            if line.hasSuffix("Power:") { inBatterySection = false; continue }
            if inBatterySection, line.hasPrefix("lowpowermode"),
               let value = line.split(whereSeparator: \.isWhitespace).last {
                return Int(value)
            }
        }
        return nil
    }
    func liveLowPowerModeEnabled() -> Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    func powerSource() -> PowerSource { Shell.pmset(["-g", "ps"]).1.contains("AC Power") ? .ac : .battery }
    func batteryPercent() -> Int? {
        let text = Shell.pmset(["-g", "batt"]).1
        guard let range = text.range(of: #"[0-9]+%"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropLast())
    }
    func lidState() -> LidState {
        let text = Shell.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).1
        if text.contains("AppleClamshellState\" = Yes") { return .closed }
        if text.contains("AppleClamshellState\" = No") { return .open }
        return .unknown
    }
    func sleepNow() { _ = Shell.pmset(["sleepnow"], sudo: true) }
}

/// The launchctl boundary for the guard job and the legacy-agent sweep.
/// (The diagnostic remnant sweep keeps its direct launchctl list call —
/// it runs off the main actor and only reads.)
protocol LaunchdAdapting: Sendable {
    @discardableResult func bootout(_ target: String) -> Int32
    @discardableResult func bootout(domain: String, plistPath: String) -> Int32
    @discardableResult func bootstrap(domain: String, plistPath: String) -> Int32
    func kickstart(_ target: String)
    func printJob(_ target: String) -> (Int32, String)
}

struct SystemLaunchdAdapter: LaunchdAdapting {
    func bootout(_ target: String) -> Int32 { Shell.run("/bin/launchctl", ["bootout", target]).0 }
    func bootout(domain: String, plistPath: String) -> Int32 {
        Shell.run("/bin/launchctl", ["bootout", domain, plistPath]).0
    }
    func bootstrap(domain: String, plistPath: String) -> Int32 {
        Shell.run("/bin/launchctl", ["bootstrap", domain, plistPath]).0
    }
    func kickstart(_ target: String) { _ = Shell.run("/bin/launchctl", ["kickstart", target]) }
    func printJob(_ target: String) -> (Int32, String) {
        Shell.run("/bin/launchctl", ["print", target])
    }
}
