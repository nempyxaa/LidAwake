import Foundation
import Testing
@testable import LidAwake

// J-01: the process-lifetime activity must not assert against idle system
// sleep. The app runs from login to logout (the watchdog restarts it), so
// an .idleSystemSleepDisabled option here is a permanent
// PreventUserIdleSystemSleep assertion — an open-lid Mac that never idle
// sleeps even with every Keep awake mode off.
@Suite struct AppActivityTests {
    @Test func standingActivityNeverDisablesIdleSystemSleep() {
        #expect(!AppActivity.options.contains(.idleSystemSleepDisabled),
                "idle: no idle-sleep assertion may be held")
        #expect(AppActivity.options.contains(.userInitiatedAllowingIdleSystemSleep))
    }

    @Test func userInitiatedWouldHaveAssertedIdleSleep() {
        // The regression guard's premise, pinned: .userInitiated is exactly
        // the sleep-asserting variant, so a revert to it flips the test above.
        #expect(ProcessInfo.ActivityOptions.userInitiated.contains(.idleSystemSleepDisabled))
        #expect(!ProcessInfo.ActivityOptions.userInitiatedAllowingIdleSystemSleep
            .contains(.idleSystemSleepDisabled))
    }
}
