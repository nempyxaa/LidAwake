import Foundation

// LidAwake v3 state machine ("Exit Signs" spec, 2026-08-12).
// Pure decisions: a MachineSnapshot goes in, a Decision (ordered effects) comes
// out. The app layer executes effects against pmset / UserDefaults / launchd.
//
// Ordering rule inside every decision: pmset effects come first, policy-flag
// effects after, notifications and logs last. The executor aborts the rest of a
// decision when a verified pmset write fails, so a failed write leaves the
// stored policy intact and the reconciling tick retries the same transition.
// The app layer advances the lid/power edge baselines only after a decision
// fully applies, so edge-triggered transitions (lid open, unplug) retry too.

public enum PowerSource: Equatable { case ac, battery }
public enum LidState: String, Equatable { case open, closed, unknown }

public enum BatteryMode: Int, Equatable, CaseIterable {
    /// "When turned on: until lid opens, N%, or hot" — one-shot, the default.
    case untilLidFloorHot = 0
    /// "When turned on: ignoring lid, until N% or hot" — one-shot.
    case ignoringLid = 1
    /// "Always when on battery: until N% or hot" — standing policy.
    case always = 2

    public var isOneShot: Bool { self != .always }
}

/// Ends the user did not cause; each one records the postmortem line.
public enum EndCause: Equatable { case floor, hot, expiry, restart }

public struct MachineSnapshot: Equatable {
    public var power: PowerSource
    public var previousPower: PowerSource
    public var batteryPercent: Int?
    public var lid: LidState
    public var previousLid: LidState
    /// ProcessInfo.ThermalState rawValue; >= 2 (serious) counts as hot.
    public var thermalState: Int
    /// Continuous seconds of nominal thermals (large when never hot).
    public var thermalOKSeconds: TimeInterval
    /// Live pmset SleepDisabled reading.
    public var sleepDisabled: Bool
    public var mode: BatteryMode
    public var oneShotActive: Bool
    /// Standing "no automatic Keep awake on power" choice (moon click).
    public var acDeclined: Bool
    /// Always mode: "Sleep on next lid close" armed.
    public var skipOnce: Bool
    /// Always mode: paused by floor or heat, waiting on the resume predicate.
    public var alwaysPaused: Bool
    /// Seconds a one-shot has been held on AC; nil when no hold clock runs.
    public var acHoldSeconds: TimeInterval?
    public var batteryFloor: Int

    public init(power: PowerSource = .battery,
                previousPower: PowerSource = .battery,
                batteryPercent: Int? = 80,
                lid: LidState = .open,
                previousLid: LidState = .open,
                thermalState: Int = 0,
                thermalOKSeconds: TimeInterval = 1_000_000,
                sleepDisabled: Bool = false,
                mode: BatteryMode = .untilLidFloorHot,
                oneShotActive: Bool = false,
                acDeclined: Bool = false,
                skipOnce: Bool = false,
                alwaysPaused: Bool = false,
                acHoldSeconds: TimeInterval? = nil,
                batteryFloor: Int = 20) {
        self.power = power
        self.previousPower = previousPower
        self.batteryPercent = batteryPercent
        self.lid = lid
        self.previousLid = previousLid
        self.thermalState = thermalState
        self.thermalOKSeconds = thermalOKSeconds
        self.sleepDisabled = sleepDisabled
        self.mode = mode
        self.oneShotActive = oneShotActive
        self.acDeclined = acDeclined
        self.skipOnce = skipOnce
        self.alwaysPaused = alwaysPaused
        self.acHoldSeconds = acHoldSeconds
        self.batteryFloor = batteryFloor
    }
}

public enum Notice: Equatable {
    case acAutoOn            // On power: keeping the Mac awake automatically…
    case batteryAutoOff      // On battery: Keep awake off…
    case manualOff           // user turned Keep awake off
    case lidEnd              // mode 1 ended by a deliberate lid open
    case floorEnd(Int)       // one-shot ended at the battery floor
    case hotEnd              // ended by heat
    case floorPaused(Int)    // Always paused at the floor (payload: floor)
    case hotPaused           // Always paused by heat
    case alwaysResumed       // Always resumed via the resume predicate
    case acExpired           // one-shot expired after 30 min on power
    case failure             // pmset enable failed
    case revertFailure       // pmset restore failed
}

public enum Effect: Equatable {
    case setSleepDisabled(Bool, verify: Bool)
    case setLowPowerMode(Bool)
    case setOneShot(Bool)
    case setACDeclined(Bool)
    case setSkipOnce(Bool)
    case setAlwaysPaused(Bool)
    case setACHold(Bool)
    case recordPostmortem(EndCause)
    case notify(Notice)
    case log(String)
    case thermalHistory
    case sleepNow
}

public struct Decision: Equatable {
    public var effects: [Effect]
    public var terminal: Bool
    public init(effects: [Effect] = [], terminal: Bool = false) {
        self.effects = effects
        self.terminal = terminal
    }
}

public enum StateMachine {
    // Hardcoded constants (spec: not Settings).
    public static let acHoldLimit: TimeInterval = 30 * 60
    public static let resumeMargin = 5
    public static let thermalCalmRequirement: TimeInterval = 5 * 60
    public static let seriousThermal = 2

    /// The single resume predicate (spec: one place in code). Gates Always
    /// resumption and resumption on unplug. One-shot arming is NOT gated on
    /// it — arming is refused only at/below the floor or while hot (spec:
    /// "Arming below floor / while hot: one-shots disabled with reason").
    public static func resumeReady(percent: Int?, floor: Int, thermalOKSeconds: TimeInterval) -> Bool {
        guard let percent else { return false }
        return percent >= floor + resumeMargin && thermalOKSeconds >= thermalCalmRequirement
    }

    /// Floor hit = at or below the floor (an unreadable battery counts as hit).
    public static func floorHit(percent: Int?, floor: Int) -> Bool {
        guard let percent else { return true }
        return percent <= floor
    }

    // MARK: - Reconciling tick

    public static func tick(_ s: MachineSnapshot) -> Decision {
        var e: [Effect] = []
        let hot = s.thermalState >= seriousThermal
        let lidOpened = s.previousLid == .closed && s.lid == .open
        let lidClosed = s.previousLid == .open && s.lid == .closed
        let unplugged = s.previousPower == .ac && s.power == .battery
        let plugged = s.previousPower == .battery && s.power == .ac

        // Skip-once and the paused flag only exist under Always.
        var skip = s.skipOnce
        if skip && s.mode != .always { e.append(.setSkipOnce(false)); skip = false }
        var paused = s.alwaysPaused
        if paused && s.mode != .always { e.append(.setAlwaysPaused(false)); paused = false }

        if s.power == .ac {
            return acTick(s, effects: e, hot: hot, lidOpened: lidOpened, plugged: plugged)
        }

        if s.acHoldSeconds != nil { e.append(.setACHold(false)) }

        if unplugged {
            if s.oneShotActive {
                // On unplug: re-check the floor (at/below ends, else continue).
                if floorHit(percent: s.batteryPercent, floor: s.batteryFloor) {
                    e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                          .setOneShot(false),
                          .recordPostmortem(.floor), .notify(.floorEnd(s.batteryPercent ?? 0)),
                          .log("one-shot ended on unplug (battery at floor)")]
                    return Decision(effects: e)
                }
                if !s.sleepDisabled { e.append(.setSleepDisabled(true, verify: true)) }
                e += [.setLowPowerMode(true), .log("one-shot continues on battery")]
                return Decision(effects: e)
            }
            if s.mode != .always {
                if s.sleepDisabled {
                    e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                          .notify(.batteryAutoOff), .log("Keep awake off (on battery)")]
                }
                return Decision(effects: e)
            }
            // Always: resumes on unplug via the single resume predicate.
            if !resumeReady(percent: s.batteryPercent, floor: s.batteryFloor, thermalOKSeconds: s.thermalOKSeconds) {
                if s.sleepDisabled { e.append(.setSleepDisabled(false, verify: true)) }
                e.append(.setLowPowerMode(false))
                if !paused {
                    e += [.setAlwaysPaused(true), .notify(pauseNotice(s)),
                          .log("Always Keep awake paused on unplug")]
                }
                return Decision(effects: e)
            }
            if paused { e.append(.setAlwaysPaused(false)); paused = false }
            if skip {
                // The promised one-time sleep is honored across the unplug:
                // do not re-enable pmset; the next lid close sleeps.
                if s.sleepDisabled { e.append(.setSleepDisabled(false, verify: true)) }
                e += [.setLowPowerMode(false), .log("one-time sleep armed across unplug")]
                return Decision(effects: e)
            }
            if !s.sleepDisabled { e.append(.setSleepDisabled(true, verify: true)) }
            e += [.setLowPowerMode(true), .log("Always Keep awake active on battery")]
            return Decision(effects: e)
        }

        // Steady battery.
        if s.mode == .always {
            return alwaysBatteryTick(s, effects: e, hot: hot, lidClosed: lidClosed, paused: paused, skip: skip)
        }

        if s.oneShotActive {
            if s.mode == .untilLidFloorHot && lidOpened {
                // Deliberate lid open: reset, no sleep, no postmortem.
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setOneShot(false), .notify(.lidEnd), .log("one-shot ended (lid opened)")]
                return Decision(effects: e)
            }
            if hot {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setOneShot(false),
                      .recordPostmortem(.hot), .notify(.hotEnd), .thermalHistory,
                      .log("thermal end (thermalState=\(s.thermalState))")]
                // Lid-scoped safety invariant: forced sleep only with the lid closed.
                if s.lid == .closed {
                    e.append(.sleepNow)
                    return Decision(effects: e, terminal: true)
                }
                return Decision(effects: e)
            }
            if floorHit(percent: s.batteryPercent, floor: s.batteryFloor) {
                // Restoring the default is enough: a closed lid then sleeps naturally.
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setOneShot(false),
                      .recordPostmortem(.floor), .notify(.floorEnd(s.batteryPercent ?? 0)),
                      .log("one-shot ended (battery at floor)")]
                return Decision(effects: e)
            }
            if !s.sleepDisabled {
                e += [.setSleepDisabled(true, verify: true), .setLowPowerMode(true),
                      .log("reconciled pmset to the armed one-shot")]
            }
            return Decision(effects: e)
        }

        // Idle on battery.
        if s.sleepDisabled {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                  .notify(.batteryAutoOff), .log("reconciled pmset to idle")]
        }
        return Decision(effects: e)
    }

    private static func acTick(_ s: MachineSnapshot, effects: [Effect],
                               hot: Bool, lidOpened: Bool, plugged: Bool) -> Decision {
        var e = effects
        var oneShot = s.oneShotActive
        // Low Power Mode is battery-scoped; drop it when we arrive on AC.
        if plugged { e.append(.setLowPowerMode(false)) }

        if oneShot {
            if s.acHoldSeconds == nil {
                e += [.setACHold(true), .log("one-shot held on power")]
            }
            if s.mode == .untilLidFloorHot && lidOpened {
                // The mode-1 contract still ends on a deliberate lid open.
                e += [.setOneShot(false), .setACHold(false), .notify(.lidEnd),
                      .log("held one-shot ended (lid opened)")]
                oneShot = false
            } else if hot {
                // Heat always ends Keep awake — on AC too, lid open or closed
                // (the safety invariant holds "in every mode"). The forced
                // sleep still runs only while the lid is closed.
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setOneShot(false), .setACHold(false),
                      .recordPostmortem(.hot), .notify(.hotEnd), .thermalHistory,
                      .log("thermal end on power (thermalState=\(s.thermalState))")]
                if s.lid == .closed {
                    e.append(.sleepNow)
                    return Decision(effects: e, terminal: true)
                }
                return Decision(effects: e)
            } else if let held = s.acHoldSeconds, held >= acHoldLimit,
                      !(s.acDeclined && s.lid == .closed) {
                // Anti-zombie expiry — except when the hold is the only thing
                // keeping a declined, closed-lid Mac awake.
                e += [.setOneShot(false), .setACHold(false),
                      .recordPostmortem(.expiry), .notify(.acExpired),
                      .log("one-shot expired after 30 min on power")]
                oneShot = false
            }
        } else if s.acHoldSeconds != nil {
            e.append(.setACHold(false))
        }

        if s.acDeclined {
            // Declined: the lid sleeps the Mac — unless a held one-shot must
            // keep a closed-lid Mac awake until unplug.
            let mustStayAwake = oneShot && s.lid == .closed
            if s.sleepDisabled && !mustStayAwake {
                e += [.setSleepDisabled(false, verify: true), .log("on-power Keep awake stays declined")]
            } else if !s.sleepDisabled && mustStayAwake {
                e += [.setSleepDisabled(true, verify: true),
                      .log("held one-shot keeps the closed-lid Mac awake (declined)")]
            }
        } else if hot {
            // The standing on-power Keep awake honors heat too: drop
            // SleepDisabled while hot (a closed lid then sleeps); the
            // automatic behavior returns once thermals recover.
            if s.sleepDisabled {
                e += [.setSleepDisabled(false, verify: true),
                      .recordPostmortem(.hot), .notify(.hotPaused), .thermalHistory,
                      .log("on-power Keep awake suspended (thermalState=\(s.thermalState))")]
                if s.lid == .closed {
                    e.append(.sleepNow)
                    return Decision(effects: e, terminal: true)
                }
            }
        } else if !s.sleepDisabled {
            e += [.setSleepDisabled(true, verify: true), .notify(.acAutoOn),
                  .log("automatic Keep awake (on power)")]
        }
        return Decision(effects: e)
    }

    private static func alwaysBatteryTick(_ s: MachineSnapshot, effects: [Effect],
                                          hot: Bool, lidClosed: Bool,
                                          paused: Bool, skip: Bool) -> Decision {
        var e = effects
        if paused {
            if s.sleepDisabled {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .log("reconciled pmset to paused Always")]
            }
            if resumeReady(percent: s.batteryPercent, floor: s.batteryFloor, thermalOKSeconds: s.thermalOKSeconds) {
                e += [.setSleepDisabled(true, verify: true), .setLowPowerMode(true),
                      .setAlwaysPaused(false), .notify(.alwaysResumed),
                      .log("Always Keep awake resumed")]
            }
            return Decision(effects: e)
        }

        if hot {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                  .setAlwaysPaused(true),
                  .recordPostmortem(.hot), .notify(.hotPaused), .thermalHistory,
                  .log("Always Keep awake paused (thermalState=\(s.thermalState))")]
            if s.lid == .closed {
                e.append(.sleepNow)
                return Decision(effects: e, terminal: true)
            }
            return Decision(effects: e)
        }
        if floorHit(percent: s.batteryPercent, floor: s.batteryFloor) {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                  .setAlwaysPaused(true),
                  .recordPostmortem(.floor), .notify(.floorPaused(s.batteryFloor)),
                  .log("Always Keep awake paused (battery at floor)")]
            return Decision(effects: e)
        }

        if skip {
            if lidClosed {
                // Consumed only by a lid-close sleep.
                e += [.setSkipOnce(false), .log("one-time sleep consumed (lid closed)")]
                if s.sleepDisabled { e.insert(.setSleepDisabled(false, verify: true), at: 0) }
                return Decision(effects: e)
            }
            if s.sleepDisabled {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .log("one-time sleep armed: next lid close sleeps")]
            }
            return Decision(effects: e)
        }

        if !s.sleepDisabled {
            e += [.setSleepDisabled(true, verify: true), .setLowPowerMode(true),
                  .log("reconciled pmset to Always Keep awake")]
        }
        return Decision(effects: e)
    }

    // MARK: - User actions

    /// Click on "Keep awake with lid closed". On power while declined this
    /// re-enables automatic Keep awake; on battery it arms the one-shot modes.
    public static func arm(_ s: MachineSnapshot) -> Decision {
        if s.power == .ac {
            guard s.acDeclined else { return Decision() }
            return Decision(effects: [
                .setSleepDisabled(true, verify: true), .setACDeclined(false),
                .notify(.acAutoOn), .log("on-power Keep awake re-enabled"),
            ])
        }
        guard s.mode.isOneShot, !s.oneShotActive else { return Decision() }
        // Spec: arming is disabled only at/below the floor or while hot. The
        // resume predicate (floor + 5, five calm minutes) gates resumption,
        // not arming.
        guard !floorHit(percent: s.batteryPercent, floor: s.batteryFloor),
              s.thermalState < seriousThermal else {
            return Decision(effects: [.log("arm refused (at/below floor or hot)")])
        }
        return Decision(effects: [
            .setSleepDisabled(true, verify: true), .setLowPowerMode(true),
            .setOneShot(true), .log("one-shot armed (mode \(s.mode.rawValue + 1))"),
        ])
    }

    /// Moon click on power: decline automatic Keep awake (standing until re-enabled).
    public static func declineOnPower(_ s: MachineSnapshot) -> Decision {
        guard s.power == .ac else { return Decision() }
        var e: [Effect] = []
        if s.sleepDisabled && !(s.oneShotActive && s.lid == .closed) {
            e.append(.setSleepDisabled(false, verify: true))
        }
        e += [.setACDeclined(true), .log("on-power Keep awake declined")]
        return Decision(effects: e)
    }

    /// "Turn off Keep awake" while a one-shot is armed or held.
    public static func turnOffOneShot(_ s: MachineSnapshot) -> Decision {
        guard s.oneShotActive else { return Decision() }
        var e: [Effect] = []
        // On power with automatic Keep awake still accepted, the standing
        // behavior keeps the Mac awake; only drop pmset otherwise.
        let keepForAC = s.power == .ac && !s.acDeclined
        if s.sleepDisabled && !keepForAC { e.append(.setSleepDisabled(false, verify: true)) }
        e += [.setLowPowerMode(false), .setOneShot(false), .setACHold(false),
              .notify(.manualOff), .log("one-shot turned off")]
        return Decision(effects: e)
    }

    /// "Turn off Always Keep awake". The caller also moves the Settings radio
    /// back to the default one-shot mode.
    public static func turnOffAlways(_ s: MachineSnapshot) -> Decision {
        var e: [Effect] = []
        if s.power == .battery && s.sleepDisabled {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false)]
        }
        e += [.setSkipOnce(false), .setAlwaysPaused(false),
              .notify(.manualOff), .log("Always Keep awake turned off")]
        return Decision(effects: e)
    }

    /// "Sleep on next lid close" / "Cancel one-time sleep". The pmset change
    /// applies immediately — a lid close within the next minute must honor the
    /// promise, not wait for the reconciling tick.
    public static func toggleSkipOnce(_ s: MachineSnapshot) -> Decision {
        guard s.mode == .always else { return Decision() }
        var e: [Effect] = []
        let arming = !s.skipOnce
        if s.power == .battery && !s.alwaysPaused {
            if arming && s.sleepDisabled {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false)]
            } else if !arming && !s.sleepDisabled {
                e += [.setSleepDisabled(true, verify: true), .setLowPowerMode(true)]
            }
        }
        e += [.setSkipOnce(arming),
              .log(arming ? "one-time sleep armed" : "one-time sleep cancelled")]
        return Decision(effects: e)
    }

    /// "Sleep now". For a one-shot this also turns Keep awake off (menu
    /// subtitle promise); Always stays on and re-engages after wake. The
    /// skip-once flag is not consumed — only a lid-close sleep consumes it.
    public static func sleepNowAction(_ s: MachineSnapshot) -> Decision {
        var e: [Effect] = []
        if s.sleepDisabled { e.append(.setSleepDisabled(false, verify: true)) }
        e.append(.setLowPowerMode(false))
        if s.oneShotActive { e += [.setOneShot(false), .setACHold(false)] }
        e += [.log("sleep now"), .sleepNow]
        return Decision(effects: e, terminal: true)
    }

    /// Settings radio change. A policy change clears skip-once; an armed
    /// one-shot keeps running under the new one-shot contract (labels update
    /// live), and switching to or from Always converts cleanly.
    public static func modeChanged(_ s: MachineSnapshot, to newMode: BatteryMode) -> Decision {
        guard newMode != s.mode else { return Decision() }
        var e: [Effect] = [.setSkipOnce(false)]
        if newMode == .always {
            if s.oneShotActive { e += [.setOneShot(false), .setACHold(false)] }
            if s.power == .battery {
                if resumeReady(percent: s.batteryPercent, floor: s.batteryFloor, thermalOKSeconds: s.thermalOKSeconds) {
                    e += [.setSleepDisabled(true, verify: true), .setLowPowerMode(true),
                          .setAlwaysPaused(false), .log("Always Keep awake selected")]
                } else {
                    // Below floor / hot: Always is still selectable — it arms paused.
                    if s.sleepDisabled { e.insert(.setSleepDisabled(false, verify: true), at: 0) }
                    e += [.setAlwaysPaused(true), .notify(pauseNotice(s)),
                          .log("Always Keep awake selected (paused)")]
                }
            } else {
                e += [.setAlwaysPaused(false), .log("Always Keep awake selected (dormant on power)")]
            }
            return Decision(effects: e)
        }
        if s.mode == .always {
            if s.power == .battery && s.sleepDisabled && !s.oneShotActive {
                e.insert(.setSleepDisabled(false, verify: true), at: 0)
                e.append(.setLowPowerMode(false))
            }
            e += [.setAlwaysPaused(false), .log("left Always Keep awake")]
        }
        return Decision(effects: e)
    }

    /// Boot-time reconcile after a restart: one-shots (and skip-once) die,
    /// Always survives. A one-shot that died records the postmortem line.
    public static func reboot(hadOneShot: Bool) -> Decision {
        var e: [Effect] = [.setSkipOnce(false), .setACHold(false)]
        if hadOneShot {
            e += [.setOneShot(false), .recordPostmortem(.restart),
                  .log("one-shot did not survive the restart")]
        }
        return Decision(effects: e)
    }

    /// System is about to sleep. A sleep that starts with the lid closed is a
    /// lid-close sleep: it consumes an armed skip-once.
    public static func systemWillSleep(_ s: MachineSnapshot) -> Decision {
        guard s.mode == .always, s.skipOnce, s.lid == .closed else { return Decision() }
        return Decision(effects: [.setSkipOnce(false), .log("one-time sleep consumed (lid closed)")])
    }

    /// Quit always reverts pmset first. Mode, decline, and the paused flag
    /// persist; one-shots and skip-once do not outlive the app.
    public static func quitCleanup() -> Decision {
        Decision(effects: [
            .setSleepDisabled(false, verify: true), .setLowPowerMode(false),
            .setOneShot(false), .setACHold(false), .setSkipOnce(false),
        ])
    }

    /// Whether anything is active enough that Quit shows its one-line confirm.
    public static func quitNeedsConfirm(_ s: MachineSnapshot) -> Bool {
        s.sleepDisabled || s.oneShotActive ||
            (s.mode == .always && s.power == .battery && !s.alwaysPaused)
    }

    /// Which resume-predicate leg is actually blocking, battery preferred:
    /// the cooling line shows only when thermals block and battery does not.
    public static func pauseBlockedByHeatOnly(_ s: MachineSnapshot) -> Bool {
        let batteryBlocks = (s.batteryPercent ?? 0) < s.batteryFloor + resumeMargin
        let thermalBlocks = s.thermalOKSeconds < thermalCalmRequirement
        return thermalBlocks && !batteryBlocks
    }

    private static func pauseNotice(_ s: MachineSnapshot) -> Notice {
        pauseBlockedByHeatOnly(s) ? .hotPaused : .floorPaused(s.batteryFloor)
    }
}
