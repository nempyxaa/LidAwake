import Foundation

enum PowerSource: Equatable { case ac, battery }
enum LidState: Equatable { case open, closed, unknown }

struct MachineSnapshot {
    var power: PowerSource
    var batteryPercent: Int?
    var sleepDisabled: Bool
    var batteryOverride: Bool
    var manualOff: Bool
    var lid: LidState
    var previousLid: LidState
    var secondsSinceLastTick: TimeInterval
    var thermalState: Int
    var thermalGuard: Bool
    var batteryFloor: Int
}

enum Notice: Equatable {
    case off, acOn, lowRefusal, batteryOn, failure, revertFailure
    case lidOpened, acAutoOn, lowRevoked, hot, batteryAutoOff
}

enum Effect: Equatable {
    case setSleepDisabled(Bool, verify: Bool)
    case setLowPowerMode(Bool)
    case setBatteryOverride(Bool)
    case setManualOff(Bool)
    case notify(Notice)
    case log(String)
    case thermalHistory
    case sleepNow
}

struct Decision {
    var effects: [Effect] = []
    var terminal = false
}

enum StateMachine {
    static func toggle(_ s: MachineSnapshot) -> Decision {
        if s.sleepDisabled {
            return Decision(effects: [
                .setManualOff(true), .setSleepDisabled(false, verify: true),
                .setLowPowerMode(false), .setBatteryOverride(false), .notify(.off)
            ])
        }
        if s.power == .ac {
            return Decision(effects: [.setManualOff(false), .setSleepDisabled(true, verify: true), .notify(.acOn)])
        }
        guard let percent = s.batteryPercent, percent >= s.batteryFloor + 5 else {
            return Decision(effects: [.notify(.lowRefusal)])
        }
        return Decision(effects: [
            .setSleepDisabled(true, verify: true), .setBatteryOverride(true),
            .setLowPowerMode(true), .notify(.batteryOn)
        ])
    }

    static func guardTick(_ s: MachineSnapshot) -> Decision {
        var e: [Effect] = []
        var override = s.batteryOverride
        var manual = s.manualOff

        if override && !s.sleepDisabled {
            e += [.setLowPowerMode(false), .setBatteryOverride(false), .log("stale-BATOK cleared (flag was off)")]
            override = false
        }
        if s.secondsSinceLastTick > 420 && (override || manual) {
            if s.power == .battery && s.sleepDisabled { e.append(.setSleepDisabled(false, verify: true)) }
            if override { e.append(.setLowPowerMode(false)) }
            e += [.setBatteryOverride(false), .setManualOff(false), .log("exceptions cleared (sleep gap = lid cycle completed)")]
            override = false; manual = false
        }
        let opened = s.previousLid == .closed && s.lid == .open
        if opened && manual {
            e += [.setManualOff(false), .log("manual-off cleared (lid cycle observed)")]
            manual = false
        }
        if opened && override {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                  .setBatteryOverride(false), .notify(.lidOpened), .log("battery-override auto-revert (lid opened)")]
            override = false
        }

        if manual && s.sleepDisabled {
            e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                  .setBatteryOverride(false), .notify(.off), .log("manual-OFF retry succeeded")]
            return Decision(effects: e)
        }

        if s.power == .ac {
            if override { e += [.setLowPowerMode(false), .setBatteryOverride(false)] }
            if !s.sleepDisabled && !manual {
                e += [.setSleepDisabled(true, verify: true), .notify(.acAutoOn), .log("auto-ON (AC)")]
            }
            return Decision(effects: e)
        }

        guard s.sleepDisabled else { return Decision(effects: e) }
        if override {
            if s.thermalGuard && s.lid == .closed && s.thermalState >= 2 {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setBatteryOverride(false), .notify(.hot), .thermalHistory,
                      .log("thermal force-sleep (thermalState=\(s.thermalState))"), .sleepNow]
                return Decision(effects: e, terminal: true)
            }
            if s.batteryPercent == nil || s.batteryPercent! < s.batteryFloor {
                e += [.setSleepDisabled(false, verify: true), .setLowPowerMode(false),
                      .setBatteryOverride(false), .notify(.lowRevoked),
                      .log("battery-override revoked (<\(s.batteryFloor)%)")]
            }
        } else {
            e += [.setSleepDisabled(false, verify: true), .notify(.batteryAutoOff), .log("auto-OFF (battery, no override)")]
        }
        return Decision(effects: e)
    }
}
