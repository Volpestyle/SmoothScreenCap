import Foundation
import ProjectModel

public struct AutoZoom {
  public struct ClickEvent: Equatable {
    public var time: Double
    public var location: Point

    public init(time: Double, location: Point) {
      self.time = time
      self.location = location
    }
  }

  public struct Point: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  public struct Size: Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
    }
  }

  public enum FocusMode: Equatable {
    case lastClick
    case weightedAverage
  }

  public struct Config: Equatable {
    public var preRoll: Double
    public var postRoll: Double
    public var settleTime: Double
    public var padding: Double
    public var defaultZoom: Double
    public var focusMode: FocusMode

    public init(
      preRoll: Double = 0.25,
      postRoll: Double = 1.0,
      settleTime: Double = 0.15,
      padding: Double = 0.0,
      defaultZoom: Double = 1.2,
      focusMode: FocusMode = .lastClick
    ) {
      self.preRoll = preRoll
      self.postRoll = postRoll
      self.settleTime = settleTime
      self.padding = padding
      self.defaultZoom = defaultZoom
      self.focusMode = focusMode
    }
  }

  public static func generateSegments(
    clicks: [ClickEvent],
    sourceSize: Size,
    outputAspectRatio: Double,
    duration: Double,
    config: Config = Config()
  ) -> [ZoomSegment] {
    guard duration > 0, sourceSize.width > 0, sourceSize.height > 0 else {
      return []
    }
    let sortedClicks = clicks.sorted { $0.time < $1.time }
    if sortedClicks.isEmpty {
      return []
    }

    var intervals: [Interval] = sortedClicks.map { click in
      let baseStart = click.time - config.preRoll
      let baseEnd = click.time + config.postRoll
      let expand = config.settleTime * 0.5
      let start = max(0, baseStart - expand)
      let end = min(duration, baseEnd + expand)
      return Interval(start: start, end: end, clicks: [click])
    }

    intervals.sort { $0.start < $1.start }
    var merged: [Interval] = []
    for interval in intervals {
      guard let last = merged.last else {
        merged.append(interval)
        continue
      }
      if interval.start <= last.end {
        var updated = last
        updated.end = max(last.end, interval.end)
        updated.clicks.append(contentsOf: interval.clicks)
        merged[merged.count - 1] = updated
      } else {
        merged.append(interval)
      }
    }

    return merged.map { interval in
      let focus = focusPoint(for: interval, mode: config.focusMode)
      let target = targetRect(
        focus: focus,
        sourceSize: sourceSize,
        outputAspectRatio: outputAspectRatio,
        zoom: config.defaultZoom,
        padding: config.padding
      )
      return ZoomSegment(
        start: interval.start,
        end: interval.end,
        mode: .auto,
        scale: config.defaultZoom,
        targetPoint: TargetPoint(x: focus.x, y: focus.y),
        targetRect: TargetRect(
          x: target.origin.x,
          y: target.origin.y,
          width: target.size.width,
          height: target.size.height
        ),
        easing: "easeInOut"
      )
    }
  }

  private struct Interval: Equatable {
    var start: Double
    var end: Double
    var clicks: [ClickEvent]
  }

  private struct Rect: Equatable {
    var origin: Point
    var size: Size
  }

  private static func focusPoint(for interval: Interval, mode: FocusMode) -> Point {
    switch mode {
    case .lastClick:
      let last = interval.clicks.max { $0.time < $1.time }
      return last?.location ?? Point(x: 0, y: 0)
    case .weightedAverage:
      var totalWeight = 0.0
      var sumX = 0.0
      var sumY = 0.0
      let sorted = interval.clicks.sorted { $0.time < $1.time }
      for (index, click) in sorted.enumerated() {
        let weight = Double(index + 1)
        sumX += click.location.x * weight
        sumY += click.location.y * weight
        totalWeight += weight
      }
      guard totalWeight > 0 else {
        return Point(x: 0, y: 0)
      }
      return Point(x: sumX / totalWeight, y: sumY / totalWeight)
    }
  }

  private static func targetRect(
    focus: Point,
    sourceSize: Size,
    outputAspectRatio: Double,
    zoom: Double,
    padding: Double
  ) -> Rect {
    let safeZoom = max(zoom, 1.0)
    let maxWidth = max(sourceSize.width - padding * 2.0, 1.0)
    let maxHeight = max(sourceSize.height - padding * 2.0, 1.0)
    let sourceAspect = maxWidth / maxHeight
    let targetAspect = max(outputAspectRatio, 0.1)

    var cropWidth = maxWidth / safeZoom
    var cropHeight = cropWidth / targetAspect
    if cropHeight > maxHeight {
      cropHeight = maxHeight / safeZoom
      cropWidth = cropHeight * targetAspect
    }

    let minX = padding
    let minY = padding
    let maxX = sourceSize.width - padding - cropWidth
    let maxY = sourceSize.height - padding - cropHeight

    var originX = focus.x - cropWidth * 0.5
    var originY = focus.y - cropHeight * 0.5

    if sourceAspect >= targetAspect {
      originX = min(max(originX, minX), maxX)
    } else {
      originX = min(max(originX, minX), maxX)
    }
    originY = min(max(originY, minY), maxY)

    return Rect(
      origin: Point(x: originX, y: originY),
      size: Size(width: cropWidth, height: cropHeight)
    )
  }
}
