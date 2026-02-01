import Foundation
import EventLog

/// Interpolates cursor position and state from event log
final class CursorInterpolator {
    struct CursorState {
        var position: CGPoint
        var isClicking: Bool
        var clickProgress: Double  // 0-1, for click animation
        var isVisible: Bool

        static let hidden = CursorState(
            position: .zero,
            isClicking: false,
            clickProgress: 0,
            isVisible: false
        )
    }

    private var entries: [EventLogEntry] = []
    private var mouseEntries: [(time: Double, entry: EventLogEntry.MouseEvent)] = []

    init(entries: [EventLogEntry]) {
        self.entries = entries
        // Pre-filter mouse events for faster lookup
        self.mouseEntries = entries.compactMap { entry in
            guard let mouse = entry.mouse else { return nil }
            return (time: entry.time, entry: mouse)
        }
    }

    convenience init(url: URL) throws {
        let entries = try EventLogReader.read(from: url)
        self.init(entries: entries)
    }

    /// Get cursor state at a specific source time
    func cursorState(at time: Double) -> CursorState {
        guard !mouseEntries.isEmpty else {
            return .hidden
        }

        // Find the mouse entry at or just before the requested time
        var lastEntry: (time: Double, entry: EventLogEntry.MouseEvent)?
        var clickTime: Double?

        for mouseEntry in mouseEntries {
            if mouseEntry.time > time {
                break
            }
            lastEntry = mouseEntry

            // Track recent clicks
            if mouseEntry.entry.action == .down {
                clickTime = mouseEntry.time
            } else if mouseEntry.entry.action == .up {
                clickTime = nil
            }
        }

        guard let entry = lastEntry else {
            return .hidden
        }

        let position = CGPoint(x: entry.entry.location.x, y: entry.entry.location.y)

        // Calculate click animation progress (fade out over 0.3 seconds)
        var clickProgress: Double = 0
        if let clickTime = clickTime {
            let elapsed = time - clickTime
            if elapsed < 0.3 {
                clickProgress = 1.0 - (elapsed / 0.3)
            }
        }

        // Check for recent clicks to show click ripple
        let isClicking = entry.entry.action == .down ||
            (clickTime != nil && time - clickTime! < 0.15)

        // Hide cursor if no movement for a while (optional, can be toggled)
        let isVisible = (time - entry.time) < 3.0 // Hide after 3 seconds of no movement

        return CursorState(
            position: position,
            isClicking: isClicking,
            clickProgress: clickProgress,
            isVisible: isVisible
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

    /// Get position interpolated between two frames for smoother playback
    func interpolatedPosition(at time: Double) -> CGPoint? {
        guard mouseEntries.count >= 2 else {
            return mouseEntries.first.map {
                CGPoint(x: $0.entry.location.x, y: $0.entry.location.y)
            }
        }

        // Find surrounding entries
        var before: (time: Double, entry: EventLogEntry.MouseEvent)?
        var after: (time: Double, entry: EventLogEntry.MouseEvent)?

        for (index, entry) in mouseEntries.enumerated() {
            if entry.time <= time {
                before = entry
            }
            if entry.time >= time && after == nil {
                after = entry
                break
            }
        }

        guard let b = before else {
            return after.map { CGPoint(x: $0.entry.location.x, y: $0.entry.location.y) }
        }

        guard let a = after, a.time > b.time else {
            return CGPoint(x: b.entry.location.x, y: b.entry.location.y)
        }

        // Linear interpolation
        let t = (time - b.time) / (a.time - b.time)
        let x = b.entry.location.x + (a.entry.location.x - b.entry.location.x) * t
        let y = b.entry.location.y + (a.entry.location.y - b.entry.location.y) * t

        return CGPoint(x: x, y: y)
    }
}
