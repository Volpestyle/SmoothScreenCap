import Foundation

public struct ProjectValidationIssue: Equatable {
  public enum Severity: String, Equatable {
    case warning
    case error
  }

  public var severity: Severity
  public var message: String

  public init(severity: Severity, message: String) {
    self.severity = severity
    self.message = message
  }
}

public struct ProjectValidationError: Error, LocalizedError {
  public let issues: [ProjectValidationIssue]

  public var errorDescription: String? {
    let messages = issues.map { "\($0.severity.rawValue.uppercased()): \($0.message)" }
    return messages.joined(separator: "\n")
  }
}

public enum ProjectValidator {
  public static func validate(_ project: ProjectModel) -> [ProjectValidationIssue] {
    var issues: [ProjectValidationIssue] = []
    let screenDuration = project.assets.screen.duration

    validateAssetDuration("screen", duration: project.assets.screen.duration, issues: &issues)
    validateAssetDuration("systemAudio", duration: project.assets.systemAudio?.duration, issues: &issues)
    validateAssetDuration("mic", duration: project.assets.mic?.duration, issues: &issues)
    validateAssetDuration("webcam", duration: project.assets.webcam?.duration, issues: &issues)

    for (index, cut) in project.edit.cuts.enumerated() {
      validateTimeRange(
        label: "cut[\(index)]",
        start: cut.start,
        end: cut.end,
        duration: screenDuration,
        issues: &issues
      )
    }

    for (index, segment) in project.edit.speedSegments.enumerated() {
      validateTimeRange(
        label: "speedSegments[\(index)]",
        start: segment.start,
        end: segment.end,
        duration: screenDuration,
        issues: &issues
      )
      if segment.rate <= 0 {
        issues.append(ProjectValidationIssue(
          severity: .error,
          message: "speedSegments[\(index)] has non-positive rate \(segment.rate)."
        ))
      } else if segment.rate < 0.1 || segment.rate > 8 {
        issues.append(ProjectValidationIssue(
          severity: .warning,
          message: "speedSegments[\(index)] rate \(segment.rate) is outside the recommended 0.1–8 range."
        ))
      }
    }

    for (index, segment) in project.edit.zoomSegments.enumerated() {
      validateTimeRange(
        label: "zoomSegments[\(index)]",
        start: segment.start,
        end: segment.end,
        duration: screenDuration,
        issues: &issues
      )
      if let scale = segment.scale, scale <= 0 {
        issues.append(ProjectValidationIssue(
          severity: .error,
          message: "zoomSegments[\(index)] has non-positive scale \(scale)."
        ))
      }
      if let rect = segment.targetRect, (rect.width <= 0 || rect.height <= 0) {
        issues.append(ProjectValidationIssue(
          severity: .error,
          message: "zoomSegments[\(index)] has invalid targetRect size \(rect.width)x\(rect.height)."
        ))
      }
    }

    for (index, override) in project.edit.cursorOverrides.enumerated() {
      validateTimeRange(
        label: "cursorOverrides[\(index)]",
        start: override.start,
        end: override.end,
        duration: screenDuration,
        issues: &issues
      )
      if let scale = override.cursorScale, scale <= 0 {
        issues.append(ProjectValidationIssue(
          severity: .error,
          message: "cursorOverrides[\(index)] has non-positive cursorScale \(scale)."
        ))
      }
    }

    return issues
  }

  public static func validateOrThrow(_ project: ProjectModel) throws {
    let issues = validate(project)
    if issues.contains(where: { $0.severity == .error }) {
      throw ProjectValidationError(issues: issues)
    }
  }

  private static func validateAssetDuration(
    _ label: String,
    duration: Double?,
    issues: inout [ProjectValidationIssue]
  ) {
    guard let duration else { return }
    if duration < 0 {
      issues.append(ProjectValidationIssue(
        severity: .error,
        message: "\(label) asset duration is negative (\(duration))."
      ))
    } else if duration == 0 {
      issues.append(ProjectValidationIssue(
        severity: .warning,
        message: "\(label) asset duration is zero."
      ))
    }
  }

  private static func validateTimeRange(
    label: String,
    start: Double,
    end: Double,
    duration: Double?,
    issues: inout [ProjectValidationIssue]
  ) {
    if start < 0 || end < 0 {
      issues.append(ProjectValidationIssue(
        severity: .error,
        message: "\(label) has negative time range (\(start)–\(end))."
      ))
      return
    }
    if end <= start {
      issues.append(ProjectValidationIssue(
        severity: .error,
        message: "\(label) has non-positive duration (\(start)–\(end))."
      ))
      return
    }
    if let duration, end > duration {
      issues.append(ProjectValidationIssue(
        severity: .warning,
        message: "\(label) end time \(end) exceeds duration \(duration)."
      ))
    }
  }
}
