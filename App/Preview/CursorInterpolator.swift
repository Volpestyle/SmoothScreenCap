import CoreGraphics
import CursorSmoothing
import EventLog
import Foundation
import ProjectModel

/// Interpolates cursor position and state from event log
final class CursorInterpolator {
    struct CursorState {
        var position: CGPoint
        var isClicking: Bool
        var clickProgress: Double  // 0-1, for click animation
        var opacity: Double

        var isVisible: Bool {
            opacity > 0.001
        }

        static let hidden = CursorState(
            position: .zero,
            isClicking: false,
            clickProgress: 0,
            opacity: 0
        )
    }

    private let microShakeThreshold: CGFloat = 2.0
    private let clickDuration: Double = 0.3
    private let clickScaleDuration: Double = 0.15
    private let idleFadeDuration: Double = 0.25

    private var mouseEntries: [(time: Double, entry: EventLogEntry.MouseEvent)] = []
    private var leftClickTimes: [Double] = []

    private var filter = OneEuroFilter()
    private var filterSettings = OneEuroFilterSettings()
    private var lastFilteredTime: Double?
    private var lastStablePosition: CGPoint?
    private var lastSmoothingEnabled: Bool?

    init(entries: [EventLogEntry]) {
        // Pre-filter mouse events for faster lookup
        self.mouseEntries = entries.compactMap { entry in
            guard let mouse = entry.mouse else { return nil }
            return (time: entry.time, entry: mouse)
        }

        self.leftClickTimes = mouseEntries.compactMap { entry in
            guard entry.entry.action == .down, entry.entry.button == .left else { return nil }
            return entry.time
        }
    }

    convenience init(url: URL) throws {
        let entries = try EventLogReader.read(from: url)
        self.init(entries: entries)
    }

    /// Get cursor state at a specific source time
    func cursorState(
        at time: Double,
        cursorSettings: CursorSettings = CursorSettings(),
        cursorOverrides: [CursorOverride] = []
    ) -> CursorState {
        guard let lastEntryIndex = lastMouseEntryIndex(at: time) else {
            return .hidden
        }

        let lastEntry = mouseEntries[lastEntryIndex]
        guard let rawPosition = rawPosition(at: time, lastEntryIndex: lastEntryIndex) else {
            return .hidden
        }

        let override = activeOverride(at: time, overrides: cursorOverrides)
        let smoothingAllowed = cursorSettings.smoothingEnabled && override?.disableSmoothing != true
        let hideOverride = override?.hideCursor == true

        let smoothedPosition: CGPoint
        if smoothingAllowed {
            let stable = applyMicroShake(to: rawPosition)
            let settings = OneEuroFilterSettings(
                minCutoff: cursorSettings.smoothingMinCutoff,
                beta: cursorSettings.smoothingBeta,
                dCutoff: cursorSettings.smoothingDCutoff
            )
            smoothedPosition = applySmoothing(to: stable, time: time, settings: settings)
        } else {
            lastStablePosition = rawPosition
            lastSmoothingEnabled = false
            lastFilteredTime = time
            smoothedPosition = rawPosition
        }

        let clickTime = lastClickTime(at: time)
        var clickProgress: Double = 0
        var isClicking = false
        if let clickTime {
            let elapsed = time - clickTime
            if elapsed >= 0, elapsed < clickDuration {
                clickProgress = 1.0 - (elapsed / clickDuration)
            }
            if elapsed >= 0, elapsed < clickScaleDuration {
                isClicking = true
            }
        }

        let opacity: Double
        if hideOverride {
            opacity = 0
        } else if !cursorSettings.idleHideEnabled {
            opacity = 1
        } else {
            let idleTime = time - lastEntry.time
            if idleTime <= cursorSettings.idleHideDelay {
                opacity = 1
            } else if idleTime >= cursorSettings.idleHideDelay + idleFadeDuration {
                opacity = 0
            } else {
                let t = (idleTime - cursorSettings.idleHideDelay) / idleFadeDuration
                opacity = max(0, min(1, 1.0 - t))
            }
        }

        return CursorState(
            position: smoothedPosition,
            isClicking: isClicking,
            clickProgress: clickProgress,
            opacity: opacity
        )
    }

    /// Get all click events for generating zoom segments
    func clickEvents() -> [(time: Double, position: CGPoint)] {
        return mouseEntries.compactMap { entry in
            guard entry.entry.action == .down,
                  entry.entry.button == .left else { return nil }
            return (
                time: entry.time,
                position: CGPoint(x: entry.entry.location.x, y: entry.entry.location.y)
            )
        }
    }

    func clickTimes(between start: Double, end: Double) -> [Double] {
        guard !leftClickTimes.isEmpty else { return [] }
        let minTime = min(start, end)
        let maxTime = max(start, end)
        let startIndex = upperBound(leftClickTimes, minTime)
        let endIndex = upperBound(leftClickTimes, maxTime)
        guard startIndex < endIndex else { return [] }
        return Array(leftClickTimes[startIndex..<endIndex])
    }

    /// Get position interpolated between two frames for smoother playback
    func interpolatedPosition(at time: Double) -> CGPoint? {
        guard let lastEntryIndex = lastMouseEntryIndex(at: time) else {
            return nil
        }
        return rawPosition(at: time, lastEntryIndex: lastEntryIndex)
    }

    private func applyMicroShake(to raw: CGPoint) -> CGPoint {
        guard let lastStablePosition else {
            self.lastStablePosition = raw
            return raw
        }
        let dx = raw.x - lastStablePosition.x
        let dy = raw.y - lastStablePosition.y
        if sqrt(dx * dx + dy * dy) < microShakeThreshold {
            return lastStablePosition
        }
        self.lastStablePosition = raw
        return raw
    }

    private func applySmoothing(
        to position: CGPoint,
        time: Double,
        settings: OneEuroFilterSettings
    ) -> CGPoint {
        let needsReset = lastFilteredTime == nil
            || time <= (lastFilteredTime ?? 0)
            || lastSmoothingEnabled != true
            || settings != filterSettings

        if needsReset {
            filter.update(settings: settings)
            filterSettings = settings
            filter.reset(position: position, time: time)
            lastFilteredTime = time
            lastSmoothingEnabled = true
            return position
        }

        if settings != filterSettings {
            filter.update(settings: settings)
            filterSettings = settings
        }

        let filtered = filter.filter(position: position, time: time)
        lastFilteredTime = time
        lastSmoothingEnabled = true
        return filtered
    }

    private func rawPosition(at time: Double, lastEntryIndex: Int) -> CGPoint? {
        let before = mouseEntries[lastEntryIndex]
        let beforePosition = CGPoint(x: before.entry.location.x, y: before.entry.location.y)

        let nextIndex = lastEntryIndex + 1
        guard nextIndex < mouseEntries.count else {
            return beforePosition
        }

        let after = mouseEntries[nextIndex]
        let afterPosition = CGPoint(x: after.entry.location.x, y: after.entry.location.y)
        guard after.time > before.time else {
            return beforePosition
        }

        let t = (time - before.time) / (after.time - before.time)
        let clampedT = max(0, min(1, t))
        let x = beforePosition.x + (afterPosition.x - beforePosition.x) * clampedT
        let y = beforePosition.y + (afterPosition.y - beforePosition.y) * clampedT
        return CGPoint(x: x, y: y)
    }

    private func lastMouseEntryIndex(at time: Double) -> Int? {
        guard !mouseEntries.isEmpty else { return nil }
        if time < mouseEntries[0].time {
            return nil
        }
        var low = 0
        var high = mouseEntries.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if mouseEntries[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private func lastClickTime(at time: Double) -> Double? {
        guard !leftClickTimes.isEmpty else { return nil }
        if time < leftClickTimes[0] {
            return nil
        }
        var low = 0
        var high = leftClickTimes.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if leftClickTimes[mid] <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return leftClickTimes[result]
    }

    private func upperBound(_ array: [Double], _ value: Double) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func activeOverride(at time: Double, overrides: [CursorOverride]) -> CursorOverride? {
        guard !overrides.isEmpty else { return nil }
        var active: CursorOverride?
        for override in overrides {
            if time >= override.start && time <= override.end {
                active = override
            }
        }
        return active
    }
}
