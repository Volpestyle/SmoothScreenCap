import Foundation

public struct TimeMapping: Equatable {
  public struct Segment: Equatable {
    public var sourceStart: Double
    public var sourceEnd: Double
    public var rate: Double
    public var outputStart: Double
    public var outputEnd: Double

    public init(
      sourceStart: Double,
      sourceEnd: Double,
      rate: Double,
      outputStart: Double,
      outputEnd: Double
    ) {
      self.sourceStart = sourceStart
      self.sourceEnd = sourceEnd
      self.rate = rate
      self.outputStart = outputStart
      self.outputEnd = outputEnd
    }
  }

  public var sourceDuration: Double
  public var segments: [Segment]

  public var outputDuration: Double {
    segments.last?.outputEnd ?? 0
  }

  public init(sourceDuration: Double, cuts: [Cut], speedSegments: [SpeedSegment]) {
    self.sourceDuration = max(0, sourceDuration)
    let normalizedCuts = TimeMapping.normalizeCuts(cuts, sourceDuration: self.sourceDuration)
    let speedIntervals = TimeMapping.buildSpeedIntervals(
      speedSegments,
      sourceDuration: self.sourceDuration
    )

    var builtSegments: [Segment] = []
    var outputCursor = 0.0
    for interval in speedIntervals {
      let keptRanges = TimeMapping.subtractCuts(
        start: interval.start,
        end: interval.end,
        cuts: normalizedCuts
      )
      for range in keptRanges {
        let duration = (range.end - range.start) / interval.rate
        let segment = Segment(
          sourceStart: range.start,
          sourceEnd: range.end,
          rate: interval.rate,
          outputStart: outputCursor,
          outputEnd: outputCursor + duration
        )
        builtSegments.append(segment)
        outputCursor += duration
      }
    }

    self.segments = builtSegments
  }

  public func outputTime(for sourceTime: Double) -> Double? {
    guard sourceTime >= 0, sourceTime <= sourceDuration else {
      return nil
    }
    for segment in segments {
      if sourceTime >= segment.sourceStart && sourceTime < segment.sourceEnd {
        return segment.outputStart + (sourceTime - segment.sourceStart) / segment.rate
      }
    }
    if sourceTime == sourceDuration, let last = segments.last {
      return last.outputEnd
    }
    return nil
  }

  public func sourceTime(for outputTime: Double) -> Double? {
    guard outputTime >= 0, outputTime <= outputDuration else {
      return nil
    }
    for segment in segments {
      if outputTime >= segment.outputStart && outputTime < segment.outputEnd {
        return segment.sourceStart + (outputTime - segment.outputStart) * segment.rate
      }
    }
    if outputTime == outputDuration, let last = segments.last {
      return last.sourceEnd
    }
    return nil
  }

  private struct SpeedInterval {
    var start: Double
    var end: Double
    var rate: Double
  }

  private static func normalizeCuts(_ cuts: [Cut], sourceDuration: Double) -> [Cut] {
    let clamped = cuts.compactMap { cut -> Cut? in
      let start = max(0, min(sourceDuration, cut.start))
      let end = max(0, min(sourceDuration, cut.end))
      if end <= start {
        return nil
      }
      return Cut(start: start, end: end)
    }.sorted { $0.start < $1.start }

    var merged: [Cut] = []
    for cut in clamped {
      guard let last = merged.last else {
        merged.append(cut)
        continue
      }
      if cut.start <= last.end {
        merged[merged.count - 1] = Cut(start: last.start, end: max(last.end, cut.end))
      } else {
        merged.append(cut)
      }
    }
    return merged
  }

  private static func buildSpeedIntervals(
    _ speedSegments: [SpeedSegment],
    sourceDuration: Double
  ) -> [SpeedInterval] {
    if sourceDuration <= 0 {
      return []
    }

    var boundaries: [Double] = [0, sourceDuration]
    let clampedSegments: [SpeedSegment] = speedSegments.compactMap { segment -> SpeedSegment? in
      let start = max(0, min(sourceDuration, segment.start))
      let end = max(0, min(sourceDuration, segment.end))
      if end <= start {
        return nil
      }
      return SpeedSegment(start: start, end: end, rate: segment.rate)
    }

    for segment in clampedSegments {
      boundaries.append(segment.start)
      boundaries.append(segment.end)
    }
    boundaries = Array(Set(boundaries)).sorted()

    var intervals: [SpeedInterval] = []
    for index in 0..<(boundaries.count - 1) {
      let start = boundaries[index]
      let end = boundaries[index + 1]
      guard end > start else { continue }
      var rate = 1.0
      for segment in clampedSegments {
        if segment.start < end && segment.end > start {
          rate = segment.rate
        }
      }
      intervals.append(SpeedInterval(start: start, end: end, rate: rate))
    }
    return intervals
  }

  private static func subtractCuts(
    start: Double,
    end: Double,
    cuts: [Cut]
  ) -> [(start: Double, end: Double)] {
    if cuts.isEmpty {
      return [(start: start, end: end)]
    }
    var ranges: [(start: Double, end: Double)] = []
    var cursor = start
    for cut in cuts {
      if cut.end <= cursor {
        continue
      }
      if cut.start >= end {
        break
      }
      if cut.start > cursor {
        ranges.append((start: cursor, end: min(cut.start, end)))
      }
      cursor = max(cursor, cut.end)
      if cursor >= end {
        break
      }
    }
    if cursor < end {
      ranges.append((start: cursor, end: end))
    }
    return ranges
  }
}
