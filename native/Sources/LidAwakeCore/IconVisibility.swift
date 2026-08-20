/// Menu bar overflow episode tracking (#4). macOS silently hides trailing
/// status items when the menu bar runs out of room (observed 18.08.2026:
/// OBS plus the system microphone indicator during a Zoom call): the app
/// keeps running and keeps protecting the machine, but the user loses the
/// only control surface and may assume it crashed. This is the pure
/// decision half — readings go in, at most one .becameHidden per episode
/// comes out, and the first visible reading ends the episode with one
/// .becameVisible. The app layer supplies the readings (is the status
/// item's button window actually on a screen?) and delivers the
/// notification.
public struct IconVisibility: Equatable {
    public enum Event: Equatable { case becameHidden, becameVisible }

    public private(set) var hiddenEpisode = false
    private var consecutiveHiddenReadings = 0

    public init() {}

    /// Feed one visibility reading. Two CONSECUTIVE hidden readings start
    /// an episode — a single one can be a launch or display-
    /// reconfiguration artifact, and notifying on it would cry wolf at
    /// every login. A visible reading resets the debounce and ends any
    /// running episode, so each separate overflow notifies exactly once
    /// each way. No repeat nagging.
    public mutating func observe(visible: Bool) -> Event? {
        if visible {
            consecutiveHiddenReadings = 0
            guard hiddenEpisode else { return nil }
            hiddenEpisode = false
            return .becameVisible
        }
        consecutiveHiddenReadings += 1
        guard consecutiveHiddenReadings >= 2, !hiddenEpisode else { return nil }
        hiddenEpisode = true
        return .becameHidden
    }
}
