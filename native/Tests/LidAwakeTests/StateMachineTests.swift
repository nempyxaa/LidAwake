import Testing
@testable import LidAwakeCore

private func snap(power: PowerSource = .battery,
                  prevPower: PowerSource? = nil,
                  battery: Int? = 80,
                  lid: LidState = .open,
                  prevLid: LidState? = nil,
                  thermal: Int = 0,
                  thermalOK: Double = 1_000_000,
                  disabled: Bool = false,
                  mode: BatteryMode = .untilLidFloorHot,
                  oneShot: Bool = false,
                  declined: Bool = false,
                  skip: Bool = false,
                  paused: Bool = false,
                  hold: Double? = nil,
                  floor: Int = 20) -> MachineSnapshot {
    MachineSnapshot(power: power, previousPower: prevPower ?? power,
                    batteryPercent: battery, lid: lid, previousLid: prevLid ?? lid,
                    thermalState: thermal, thermalOKSeconds: thermalOK,
                    sleepDisabled: disabled, mode: mode, oneShotActive: oneShot,
                    acDeclined: declined, skipOnce: skip, alwaysPaused: paused,
                    acHoldSeconds: hold, batteryFloor: floor)
}

private extension Decision {
    var sleeps: Bool { effects.contains(.sleepNow) }
    var restoresDefault: Bool { effects.contains(.setSleepDisabled(false, verify: true)) }
    var enables: Bool { effects.contains(.setSleepDisabled(true, verify: true)) }
    var endsOneShot: Bool { effects.contains(.setOneShot(false)) }
    var postmortems: [EndCause] {
        effects.compactMap { if case let .recordPostmortem(c) = $0 { return c } else { return nil } }
    }
}

// MARK: - Mode terminators

@Suite struct ModeTerminatorTests {
    @Test func mode1LidOpenEndsWithResetAndNoSleep() {
        let d = StateMachine.tick(snap(lid: .open, prevLid: .closed, disabled: true,
                                       mode: .untilLidFloorHot, oneShot: true))
        #expect(d.endsOneShot)
        #expect(d.restoresDefault)
        #expect(!d.sleeps, "a deliberate lid open resets, it never sleeps")
        #expect(d.postmortems.isEmpty, "user-caused ends record no postmortem")
        #expect(d.effects.contains(.notify(.lidEnd)))
    }

    @Test func mode1FloorEnds() {
        let d = StateMachine.tick(snap(battery: 20, lid: .closed, disabled: true,
                                       mode: .untilLidFloorHot, oneShot: true))
        #expect(d.endsOneShot)
        #expect(d.postmortems == [.floor])
        #expect(d.effects.contains(.notify(.floorEnd(20))))
    }

    @Test func mode1HotEnds() {
        let d = StateMachine.tick(snap(lid: .closed, thermal: 2, disabled: true,
                                       mode: .untilLidFloorHot, oneShot: true))
        #expect(d.endsOneShot)
        #expect(d.postmortems == [.hot])
    }

    @Test func mode2SurvivesLidOpen() {
        let d = StateMachine.tick(snap(lid: .open, prevLid: .closed, disabled: true,
                                       mode: .ignoringLid, oneShot: true))
        #expect(!d.endsOneShot, "mode 2 ignores the lid")
        #expect(!d.restoresDefault)
    }

    @Test func mode2FloorAndHotStillEnd() {
        let floor = StateMachine.tick(snap(battery: 19, lid: .closed, disabled: true,
                                           mode: .ignoringLid, oneShot: true))
        #expect(floor.endsOneShot)
        #expect(floor.postmortems == [.floor])
        let hot = StateMachine.tick(snap(lid: .closed, thermal: 2, disabled: true,
                                         mode: .ignoringLid, oneShot: true))
        #expect(hot.endsOneShot)
        #expect(hot.postmortems == [.hot])
    }

    @Test func unreadableBatteryCountsAsFloorHit() {
        let d = StateMachine.tick(snap(battery: nil, lid: .closed, disabled: true, oneShot: true))
        #expect(d.endsOneShot)
    }

    @Test func floorAboveBatteryAfterFloorChangeEndsCurrent() {
        // Floor raised to 30 while armed at 25%: below-new-floor is a floor hit.
        let d = StateMachine.tick(snap(battery: 25, lid: .closed, disabled: true,
                                       oneShot: true, floor: 30))
        #expect(d.endsOneShot)
        #expect(d.postmortems == [.floor])
    }
}

// MARK: - Lid-scoped safety invariant

@Suite struct LidScopedInvariantTests {
    @Test func hotWithLidClosedForcesSleep() {
        let d = StateMachine.tick(snap(lid: .closed, thermal: 2, disabled: true, oneShot: true))
        #expect(d.sleeps)
        #expect(d.terminal)
        #expect(d.effects.contains(.thermalHistory))
    }

    @Test func hotWithLidOpenDisarmsWithoutSleep() {
        let d = StateMachine.tick(snap(lid: .open, thermal: 2, disabled: true, oneShot: true))
        #expect(d.endsOneShot, "heat always ends Keep awake")
        #expect(d.restoresDefault, "default pmset is restored")
        #expect(!d.sleeps, "never sleep an open, in-use Mac")
        #expect(!d.terminal)
    }

    @Test func floorWithLidClosedRestoresDefaultWithoutExplicitSleep() {
        // Restoring the default is enough; the closed lid then sleeps naturally.
        let d = StateMachine.tick(snap(battery: 18, lid: .closed, disabled: true, oneShot: true))
        #expect(d.restoresDefault)
        #expect(!d.sleeps)
    }

    @Test func floorWithLidOpenDisarmsWithoutSleep() {
        let d = StateMachine.tick(snap(battery: 18, lid: .open, disabled: true, oneShot: true))
        #expect(d.endsOneShot)
        #expect(!d.sleeps)
    }

    @Test func alwaysHotLidClosedSleepsButLidOpenDoesNot() {
        let closed = StateMachine.tick(snap(lid: .closed, thermal: 2, disabled: true, mode: .always))
        #expect(closed.sleeps)
        #expect(closed.effects.contains(.setAlwaysPaused(true)))
        let open = StateMachine.tick(snap(lid: .open, thermal: 2, disabled: true, mode: .always))
        #expect(!open.sleeps)
        #expect(open.effects.contains(.setAlwaysPaused(true)))
    }
}

// MARK: - AC / power transitions

@Suite struct PowerTransitionTests {
    @Test func pluggingInNeverSleepsByItself() {
        for lid in [LidState.open, .closed] {
            for oneShot in [false, true] {
                let d = StateMachine.tick(snap(power: .ac, prevPower: .battery, lid: lid,
                                               disabled: oneShot, oneShot: oneShot))
                #expect(!d.sleeps, "plug-in must not sleep (lid \(lid), oneShot \(oneShot))")
            }
        }
    }

    @Test func onlyHeatForceSleepsMidTransitionLidClosed() {
        let d = StateMachine.tick(snap(power: .ac, prevPower: .battery, lid: .closed,
                                       thermal: 2, disabled: true, oneShot: true))
        #expect(d.sleeps)
        #expect(d.postmortems == [.hot])
    }

    @Test func acAutoKeepAwake() {
        let d = StateMachine.tick(snap(power: .ac))
        #expect(d.enables)
        #expect(d.effects.contains(.notify(.acAutoOn)))
    }

    @Test func declinedACStaysAsleepCapable() {
        let d = StateMachine.tick(snap(power: .ac, disabled: true, declined: true))
        #expect(d.restoresDefault)
        let idle = StateMachine.tick(snap(power: .ac, declined: true))
        #expect(!idle.enables, "declined: no automatic Keep awake")
    }

    @Test func holdClockStartsWhenOneShotArrivesOnAC() {
        let d = StateMachine.tick(snap(power: .ac, prevPower: .battery, disabled: true,
                                       oneShot: true, hold: nil))
        #expect(d.effects.contains(.setACHold(true)))
        #expect(!d.endsOneShot)
    }

    @Test func holdExpiresAfterThirtyMinutes() {
        let d = StateMachine.tick(snap(power: .ac, lid: .closed, disabled: true,
                                       oneShot: true, hold: 1800))
        #expect(d.endsOneShot)
        #expect(d.postmortems == [.expiry])
        #expect(d.effects.contains(.notify(.acExpired)))
        #expect(!d.sleeps)
    }

    @Test func holdDoesNotExpireBeforeThirtyMinutes() {
        let d = StateMachine.tick(snap(power: .ac, lid: .closed, disabled: true,
                                       oneShot: true, hold: 1799))
        #expect(!d.endsOneShot)
    }

    @Test func declinedClosedLidHoldNeverExpires() {
        let d = StateMachine.tick(snap(power: .ac, lid: .closed, disabled: true,
                                       oneShot: true, declined: true, hold: 7200))
        #expect(!d.endsOneShot, "never let the transition sleep a working closed-lid Mac")
        #expect(!d.restoresDefault)
    }

    @Test func declinedOpenLidHoldStillExpires() {
        let d = StateMachine.tick(snap(power: .ac, lid: .open, disabled: true,
                                       oneShot: true, declined: true, hold: 1800))
        #expect(d.endsOneShot)
    }

    @Test func declinedClosedLidHoldKeepsPmsetOn() {
        let d = StateMachine.tick(snap(power: .ac, lid: .closed, disabled: false,
                                       oneShot: true, declined: true, hold: 60))
        #expect(d.enables, "the hold is the only thing keeping the closed lid awake")
    }

    @Test func unplugRechecksFloorAtOrBelowEnds() {
        let d = StateMachine.tick(snap(power: .battery, prevPower: .ac, battery: 20,
                                       lid: .closed, disabled: true, oneShot: true, hold: 300))
        #expect(d.endsOneShot)
        #expect(d.postmortems == [.floor])
        #expect(d.effects.contains(.setACHold(false)))
    }

    @Test func unplugAboveFloorContinuesWithoutOffNotice() {
        let d = StateMachine.tick(snap(power: .battery, prevPower: .ac, battery: 60,
                                       lid: .closed, disabled: true, oneShot: true, hold: 300))
        #expect(!d.endsOneShot)
        #expect(!d.effects.contains(.notify(.batteryAutoOff)))
        #expect(d.effects.contains(.setLowPowerMode(true)))
    }

    @Test func plainUnplugTurnsACKeepAwakeOff() {
        let d = StateMachine.tick(snap(power: .battery, prevPower: .ac, disabled: true))
        #expect(d.restoresDefault)
        #expect(d.effects.contains(.notify(.batteryAutoOff)))
    }

    @Test func declinedUnplugIsSilent() {
        let d = StateMachine.tick(snap(power: .battery, prevPower: .ac, declined: true))
        #expect(!d.effects.contains(.notify(.batteryAutoOff)))
        #expect(!d.restoresDefault)
    }

    @Test func alwaysResumesOnUnplugViaPredicate() {
        let ready = StateMachine.tick(snap(power: .battery, prevPower: .ac, battery: 60,
                                           disabled: true, mode: .always))
        #expect(!ready.restoresDefault)
        #expect(ready.effects.contains(.setLowPowerMode(true)))
        let notReady = StateMachine.tick(snap(power: .battery, prevPower: .ac, battery: 22,
                                              disabled: true, mode: .always))
        #expect(notReady.restoresDefault)
        #expect(notReady.effects.contains(.setAlwaysPaused(true)))
    }

    @Test func armOnDeclinedPowerReenablesAuto() {
        let d = StateMachine.arm(snap(power: .ac, declined: true))
        #expect(d.enables)
        #expect(d.effects.contains(.setACDeclined(false)))
    }

    @Test func turnOffHeldOneShotKeepsACAuto() {
        let d = StateMachine.turnOffOneShot(snap(power: .ac, disabled: true, oneShot: true, hold: 60))
        #expect(d.endsOneShot)
        #expect(!d.restoresDefault, "automatic on-power Keep awake stays")
        let declined = StateMachine.turnOffOneShot(snap(power: .ac, disabled: true, oneShot: true,
                                                        declined: true, hold: 60))
        #expect(declined.restoresDefault)
    }
}

// MARK: - Resume predicate hysteresis

@Suite struct ResumePredicateTests {
    @Test func floorPlusFiveBoundary() {
        #expect(!StateMachine.resumeReady(percent: 24, floor: 20, thermalOKSeconds: 301))
        #expect(StateMachine.resumeReady(percent: 25, floor: 20, thermalOKSeconds: 301))
        #expect(!StateMachine.resumeReady(percent: nil, floor: 20, thermalOKSeconds: 301))
    }

    @Test func fiveMinuteThermalCalmBoundary() {
        #expect(!StateMachine.resumeReady(percent: 80, floor: 20, thermalOKSeconds: 299))
        #expect(StateMachine.resumeReady(percent: 80, floor: 20, thermalOKSeconds: 300))
    }

    @Test func recomputedOnFloorChange() {
        #expect(StateMachine.resumeReady(percent: 27, floor: 20, thermalOKSeconds: 400))
        #expect(!StateMachine.resumeReady(percent: 27, floor: 25, thermalOKSeconds: 400))
    }

    @Test func pausedAlwaysResumesOnlyWhenReady() {
        let stillLow = StateMachine.tick(snap(battery: 24, mode: .always, paused: true))
        #expect(!stillLow.enables)
        let stillWarm = StateMachine.tick(snap(battery: 60, thermalOK: 200, mode: .always, paused: true))
        #expect(!stillWarm.enables)
        let ready = StateMachine.tick(snap(battery: 25, thermalOK: 300, mode: .always, paused: true))
        #expect(ready.enables)
        #expect(ready.effects.contains(.setAlwaysPaused(false)))
        #expect(ready.effects.contains(.notify(.alwaysResumed)))
    }

    @Test func armGateUsesTheSamePredicate() {
        #expect(!StateMachine.arm(snap(battery: 24)).enables)
        #expect(StateMachine.arm(snap(battery: 25)).enables)
        #expect(!StateMachine.arm(snap(battery: 80, thermalOK: 100)).enables,
                "arming while cooling down is refused")
    }
}

// MARK: - Always mode & skip-once

@Suite struct AlwaysModeTests {
    @Test func alwaysKeepsAwakeThroughLidCycles() {
        let close = StateMachine.tick(snap(lid: .closed, prevLid: .open, disabled: true, mode: .always))
        #expect(!close.restoresDefault)
        let open = StateMachine.tick(snap(lid: .open, prevLid: .closed, disabled: true, mode: .always))
        #expect(!open.restoresDefault, "Always survives lid opens")
    }

    @Test func alwaysArmsItselfOnBattery() {
        let d = StateMachine.tick(snap(mode: .always))
        #expect(d.enables, "every lid close on battery keeps awake, no click needed")
    }

    @Test func alwaysFloorPausesWithPostmortem() {
        let d = StateMachine.tick(snap(battery: 20, lid: .closed, disabled: true, mode: .always))
        #expect(d.effects.contains(.setAlwaysPaused(true)))
        #expect(d.postmortems == [.floor])
        #expect(d.effects.contains(.notify(.floorPaused(20))))
        #expect(!d.sleeps, "restoring the default lets the closed lid sleep naturally")
    }

    @Test func skipOnceHoldsSleepOpenForNextClose() {
        let d = StateMachine.tick(snap(disabled: true, mode: .always, skip: true))
        #expect(d.restoresDefault, "with one-time sleep armed the next close must sleep")
        #expect(!d.effects.contains(.setSkipOnce(false)))
    }

    @Test func skipOnceConsumedOnlyByLidCloseSleep() {
        let close = StateMachine.tick(snap(lid: .closed, prevLid: .open, mode: .always, skip: true))
        #expect(close.effects.contains(.setSkipOnce(false)))
        let sleepNow = StateMachine.sleepNowAction(snap(disabled: true, mode: .always, skip: true))
        #expect(!sleepNow.effects.contains(.setSkipOnce(false)),
                "Sleep now is not a lid-close sleep")
        let willSleepOpen = StateMachine.systemWillSleep(snap(lid: .open, mode: .always, skip: true))
        #expect(willSleepOpen.effects.isEmpty)
        let willSleepClosed = StateMachine.systemWillSleep(snap(lid: .closed, mode: .always, skip: true))
        #expect(willSleepClosed.effects.contains(.setSkipOnce(false)))
    }

    @Test func skipOnceClearedByPolicyChange() {
        let d = StateMachine.modeChanged(snap(mode: .always, skip: true), to: .untilLidFloorHot)
        #expect(d.effects.contains(.setSkipOnce(false)))
    }

    @Test func skipOnceOutsideAlwaysIsScrubbed() {
        let d = StateMachine.tick(snap(mode: .untilLidFloorHot, skip: true))
        #expect(d.effects.contains(.setSkipOnce(false)))
    }

    @Test func selectingAlwaysBelowFloorArmsPaused() {
        let d = StateMachine.modeChanged(snap(battery: 15), to: .always)
        #expect(d.effects.contains(.setAlwaysPaused(true)))
        #expect(d.effects.contains(.notify(.floorPaused(20))))
        #expect(!d.enables)
    }

    @Test func selectingAlwaysHealthyEnables() {
        let d = StateMachine.modeChanged(snap(battery: 60), to: .always)
        #expect(d.enables)
    }

    @Test func turnOffAlwaysRestoresDefaultOnBattery() {
        let d = StateMachine.turnOffAlways(snap(disabled: true, mode: .always))
        #expect(d.restoresDefault)
        #expect(d.effects.contains(.setSkipOnce(false)))
    }
}

// MARK: - Reboot semantics

@Suite struct RebootTests {
    @Test func oneShotsDieAtRebootWithPostmortem() {
        let d = StateMachine.reboot(hadOneShot: true)
        #expect(d.effects.contains(.setOneShot(false)))
        #expect(d.postmortems == [.restart])
        #expect(d.effects.contains(.setSkipOnce(false)), "skip-once dies at reboot")
        #expect(d.effects.contains(.setACHold(false)))
    }

    @Test func alwaysSurvivesReboot() {
        let d = StateMachine.reboot(hadOneShot: false)
        #expect(d.postmortems.isEmpty)
        #expect(!d.effects.contains(.setAlwaysPaused(false)),
                "the standing policy and its paused flag are untouched")
        // After reboot the reconciling tick re-arms Always from the stored mode.
        let next = StateMachine.tick(snap(mode: .always))
        #expect(next.enables)
    }
}

// MARK: - Reconciliation, quit, postmortem rule

@Suite struct ReconcileTests {
    @Test func launchReconcilesPmsetToStoredPolicy() {
        let armed = StateMachine.tick(snap(lid: .closed, disabled: false, oneShot: true))
        #expect(armed.enables, "stored one-shot re-applies pmset after crash/relaunch")
        let idle = StateMachine.tick(snap(disabled: true))
        #expect(idle.restoresDefault, "idle policy turns a stray pmset flag off")
    }

    @Test func pmsetComesBeforePolicyFlagsInEnds() {
        let d = StateMachine.tick(snap(battery: 18, lid: .closed, disabled: true, oneShot: true))
        let pmset = d.effects.firstIndex(of: .setSleepDisabled(false, verify: true))
        let flag = d.effects.firstIndex(of: .setOneShot(false))
        #expect(pmset != nil && flag != nil && pmset! < flag!,
                "a failed pmset write must abort before policy is cleared")
    }

    @Test func quitCleanupRevertsFirstAndConfirmGate() {
        let d = StateMachine.quitCleanup()
        #expect(d.effects.first == .setSleepDisabled(false, verify: true))
        #expect(StateMachine.quitNeedsConfirm(snap(disabled: true)))
        #expect(StateMachine.quitNeedsConfirm(snap(mode: .always)))
        #expect(!StateMachine.quitNeedsConfirm(snap(mode: .always, paused: true)))
        #expect(!StateMachine.quitNeedsConfirm(snap()))
    }

    @Test func postmortemOnlyForEndsTheUserDidNotCause() {
        let lidOpen = StateMachine.tick(snap(lid: .open, prevLid: .closed, disabled: true, oneShot: true))
        #expect(lidOpen.postmortems.isEmpty)
        let manual = StateMachine.turnOffOneShot(snap(disabled: true, oneShot: true))
        #expect(manual.postmortems.isEmpty)
        let sleepNow = StateMachine.sleepNowAction(snap(disabled: true, oneShot: true))
        #expect(sleepNow.postmortems.isEmpty)
    }
}

// MARK: - Canonical strings and the proper-name rule

@Suite struct StringRuleTests {
    @Test func bannedTermsNeverAppear() {
        for floor in [10, 15, 20, 25, 30] {
            for s in V3Strings.allStrings(floor: floor) {
                for banned in ["keep-awake", "staying awake", "night mode", "Night mode", "Keep Awake"] {
                    #expect(!s.contains(banned), "'\(banned)' in: \(s)")
                }
            }
        }
    }

    @Test func canonicalStringsByteMatchTheSpec() {
        #expect(V3Strings.idleHeader == "Lid closed: sleeps")
        #expect(V3Strings.oneShotHeader == "Lid closed: Keep awake")
        #expect(V3Strings.alwaysHeader == "Lid closed: every time Keep awake")
        #expect(V3Strings.acHeaderOn == "Lid closed: Keep awake (on power)")
        #expect(V3Strings.acHeaderDeclined == "Lid closed: sleeps (on power)")
        #expect(V3Strings.acHoldHeader == "On power: Keep awake resumes on battery")
        #expect(V3Strings.battery(40) == "Battery: 40%")
        #expect(V3Strings.batteryCharging(78) == "Battery: 78%, charging")
        #expect(V3Strings.untilOneShotLid(20) == "Until: lid opens, 20%, or hot")
        #expect(V3Strings.untilOneShotIgnoringLid(20) == "Until: 20% or hot — ignores lid")
        #expect(V3Strings.alwaysUntil(20) == "Until 20% or hot, always")
        #expect(V3Strings.pausedFloor(20) == "Keep awake resumes at 25%")
        #expect(V3Strings.pausedHot == "Paused: cooling down")
        #expect(V3Strings.postmortem(18, "14:05") == "Last Keep awake: ended at 18%, 14:05")
        #expect(V3Strings.armItem == "Keep awake with lid closed")
        #expect(V3Strings.armSubUntilLid(20) == "Until lid opens, 20%, or hot")
        #expect(V3Strings.armSubIgnoringLid(20) == "Ignoring lid, until 20% or hot")
        #expect(V3Strings.armSubChangeMode == "Change mode in Settings")
        #expect(V3Strings.armSubOnPower == "On power: Keep awake automatically")
        #expect(V3Strings.turnOff == "Turn off Keep awake")
        #expect(V3Strings.sleepNowSubOneShot == "Sleeps and turns Keep awake off")
        #expect(V3Strings.skipOnceItem == "Sleep on next lid close")
        #expect(V3Strings.skipOnceSub == "Always Keep awake stays on")
        #expect(V3Strings.skipOnceArmedItem == "Cancel one-time sleep")
        #expect(V3Strings.turnOffAlwaysItem == "Turn off Always Keep awake")
        #expect(V3Strings.turnOffAlwaysSub == "Keep awake only when you click it")
        #expect(V3Strings.modeSection == "On battery, Keep awake")
        #expect(V3Strings.modeRadioUntilLid(20) == "When turned on: until lid opens, 20%, or hot")
        #expect(V3Strings.modeRadioIgnoringLid(20) == "When turned on: ignoring lid, until 20% or hot")
        #expect(V3Strings.modeRadioAlways(20) == "Always when on battery: until 20% or hot")
        #expect(V3Strings.quit == "Quit Lid Awake")
        #expect(V3Strings.quitConfirm == "Quitting turns off Keep awake; next lid close sleeps.")
        #expect(V3Strings.notifyACOn ==
                "On power: keeping the Mac awake automatically. Click the moon to turn off.")
        #expect(V3Strings.notifyBatteryOff ==
                "On battery: Keep awake off, the lid sleeps the Mac as usual.")
        #expect(V3Strings.notifyOverheatInvariant == "Overheat protection is now always on")
        #expect(V3Strings.floorOptionEndsCurrent(30) == "30% — ends current Keep awake")
    }

    @Test func floorRendersLiveInEveryStringThatMentionsIt() {
        #expect(V3Strings.modeRadioUntilLid(30) == "When turned on: until lid opens, 30%, or hot")
        #expect(V3Strings.modeRadioIgnoringLid(10) == "When turned on: ignoring lid, until 10% or hot")
        #expect(V3Strings.modeRadioAlways(25) == "Always when on battery: until 25% or hot")
        #expect(V3Strings.pausedFloor(30) == "Keep awake resumes at 35%")
        #expect(V3Strings.untilOneShotLid(15) == "Until: lid opens, 15%, or hot")
    }
}
