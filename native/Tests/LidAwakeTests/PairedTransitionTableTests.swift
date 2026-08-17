import Testing
@testable import LidAwakeCore

// J-10: the paired-transition table. Two events landing in ONE snapshot —
// a power edge plus a lid edge, heat, the floor, or an unreadable
// battery — asserted against the contract, not exact effect lists. Both
// v3.0.0 transition bugs (J-03, J-04) were pairs like these; every new
// pairing belongs in this table.

@Suite struct PairedTransitionTableTests {
    struct Pair {
        let name: String
        let snapshot: MachineSnapshot
        let endsOneShot: Bool
        let postmortems: [EndCause]
        let sleeps: Bool
    }

    static func snapshot(power: PowerSource = .battery,
                         prevPower: PowerSource,
                         battery: Int? = 60,
                         lid: LidState = .closed,
                         prevLid: LidState? = nil,
                         thermal: Int = 0,
                         mode: BatteryMode = .untilLidFloorHot,
                         oneShot: Bool = true,
                         hold: Double? = nil) -> MachineSnapshot {
        MachineSnapshot(power: power, previousPower: prevPower,
                        batteryPercent: battery, lid: lid, previousLid: prevLid ?? lid,
                        thermalState: thermal, thermalOKSeconds: thermal >= 2 ? 0 : 1_000_000,
                        sleepDisabled: true, mode: mode, oneShotActive: oneShot,
                        acHoldSeconds: hold)
    }

    static let table: [Pair] = [
        Pair(name: "unplug+hot mode1 lidClosed",
             snapshot: snapshot(prevPower: .ac, thermal: 3, hold: 300),
             endsOneShot: true, postmortems: [.hot], sleeps: true),
        Pair(name: "unplug+hot mode2 lidOpen",
             snapshot: snapshot(prevPower: .ac, lid: .open, thermal: 2, mode: .ignoringLid, hold: 300),
             endsOneShot: true, postmortems: [.hot], sleeps: false),
        Pair(name: "unplug+lidOpened mode1",
             snapshot: snapshot(prevPower: .ac, lid: .open, prevLid: .closed, hold: 300),
             endsOneShot: true, postmortems: [], sleeps: false),
        Pair(name: "unplug+lidOpened mode2 continues",
             snapshot: snapshot(prevPower: .ac, lid: .open, prevLid: .closed, mode: .ignoringLid, hold: 300),
             endsOneShot: false, postmortems: [], sleeps: false),
        Pair(name: "unplug+floor mode2",
             snapshot: snapshot(prevPower: .ac, battery: 15, mode: .ignoringLid, hold: 300),
             endsOneShot: true, postmortems: [.floor], sleeps: false),
        Pair(name: "unplug+batteryUnavailable mode1",
             snapshot: snapshot(prevPower: .ac, battery: nil, hold: 300),
             endsOneShot: true, postmortems: [.batteryUnavailable], sleeps: false),
        Pair(name: "unplug+hot+lidOpened mode1: lid open wins, no postmortem",
             snapshot: snapshot(prevPower: .ac, lid: .open, prevLid: .closed, thermal: 2, hold: 300),
             endsOneShot: true, postmortems: [], sleeps: false),
        Pair(name: "plug+hot mode1 lidClosed",
             snapshot: snapshot(power: .ac, prevPower: .battery, thermal: 2),
             endsOneShot: true, postmortems: [.hot], sleeps: true),
        Pair(name: "plug+lidOpened mode1 ends hold without sleep",
             snapshot: snapshot(power: .ac, prevPower: .battery, lid: .open, prevLid: .closed, hold: 60),
             endsOneShot: true, postmortems: [], sleeps: false),
        Pair(name: "plug+floor holds (floor re-checks on unplug, not on power)",
             snapshot: snapshot(power: .ac, prevPower: .battery, battery: 15, mode: .ignoringLid),
             endsOneShot: false, postmortems: [], sleeps: false),
        Pair(name: "lidClosed+hot Always pauses and sleeps",
             snapshot: snapshot(prevPower: .battery, prevLid: .open, thermal: 2, mode: .always, oneShot: false),
             endsOneShot: false, postmortems: [.hot], sleeps: true),
        Pair(name: "lidOpened+floor mode1: lid open wins, no postmortem",
             snapshot: snapshot(prevPower: .battery, battery: 15, lid: .open, prevLid: .closed),
             endsOneShot: true, postmortems: [], sleeps: false),
    ]

    @Test func pairedTransitionsHonorTheContract() {
        for pair in Self.table {
            let d = StateMachine.tick(pair.snapshot)
            let ends = d.effects.contains(.setOneShot(false))
            let postmortems = d.effects.compactMap { effect -> EndCause? in
                if case let .recordPostmortem(cause) = effect { return cause } else { return nil }
            }
            let sleeps = d.effects.contains(.sleepNow)
            #expect(ends == pair.endsOneShot, "\(pair.name)")
            #expect(postmortems == pair.postmortems, "\(pair.name)")
            #expect(sleeps == pair.sleeps, "\(pair.name)")
            #expect(!(sleeps && pair.snapshot.lid == .open),
                    "invariant: never force-sleep an open Mac — \(pair.name)")
            #expect(sleeps ? d.terminal : true,
                    "a forced sleep is always a terminal decision — \(pair.name)")
        }
    }
}
