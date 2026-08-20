import LidAwakeCore
import Testing

// #4: the overflow episode machine — one notification per episode each
// way, debounced so a launch or display-reconfiguration artifact never
// cries wolf.

@Suite struct IconVisibilityTests {
    @Test func singleHiddenReadingIsAnArtifactNotAnEpisode() {
        var v = IconVisibility()
        #expect(v.observe(visible: false) == nil)
        #expect(v.observe(visible: true) == nil, "a transient artifact never notifies either way")
        #expect(!v.hiddenEpisode)
    }

    @Test func secondConsecutiveHiddenReadingStartsTheEpisodeOnce() {
        var v = IconVisibility()
        #expect(v.observe(visible: false) == nil)
        #expect(v.observe(visible: false) == .becameHidden)
        #expect(v.hiddenEpisode)
        #expect(v.observe(visible: false) == nil, "no repeat nagging within an episode")
        #expect(v.observe(visible: true) == .becameVisible)
        #expect(v.observe(visible: true) == nil)
    }

    @Test func visibleReadingResetsTheDebounce() {
        var v = IconVisibility()
        _ = v.observe(visible: false)
        _ = v.observe(visible: true)
        #expect(v.observe(visible: false) == nil, "the two-reading debounce restarts")
        #expect(v.observe(visible: false) == .becameHidden)
    }

    @Test func separateOverflowsNotifyAgain() {
        var v = IconVisibility()
        _ = v.observe(visible: false)
        #expect(v.observe(visible: false) == .becameHidden)
        #expect(v.observe(visible: true) == .becameVisible)
        _ = v.observe(visible: false)
        #expect(v.observe(visible: false) == .becameHidden, "a new overflow is a new episode")
    }
}
