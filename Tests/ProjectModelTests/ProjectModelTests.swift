import XCTest
import ProjectModel

final class ProjectModelTests: XCTestCase {
  func testRoundTripJSON() throws {
    let project = makeSampleProject()
    let encoded = try project.encodedJSON(prettyPrinted: false)
    let decoded = try ProjectModel.decodeJSON(encoded)
    XCTAssertEqual(decoded, project)
  }

  func testISO8601Dates() throws {
    let formatter = ISO8601DateFormatter()
    let date = formatter.date(from: "2025-01-01T00:00:00Z")!
    var project = makeSampleProject()
    project.createdAt = date

    let encoded = try project.encodedJSON(prettyPrinted: false)
    let json = String(decoding: encoded, as: UTF8.self)
    XCTAssertTrue(json.contains("\"createdAt\":\"2025-01-01T00:00:00Z\""))

    let decoded = try ProjectModel.decodeJSON(encoded)
    XCTAssertEqual(decoded.createdAt, date)
  }

  private func makeSampleProject() -> ProjectModel {
    let assets = Assets(
      screen: AssetRef(
        path: "screen.mov",
        type: .screen,
        codec: "h264",
        duration: 12.5,
        width: 1920,
        height: 1080,
        timebase: 1.0 / 60.0
      ),
      mic: AssetRef(
        path: "mic.m4a",
        type: .mic,
        codec: "aac",
        duration: 12.5,
        sampleRate: 48_000,
        channels: 1,
        timebase: 1.0 / 48_000.0
      ),
      systemAudio: AssetRef(
        path: "system.m4a",
        type: .systemAudio,
        codec: "aac",
        duration: 12.5,
        sampleRate: 48_000,
        channels: 2,
        timebase: 1.0 / 48_000.0
      ),
      webcam: AssetRef(
        path: "webcam.mov",
        type: .webcam,
        codec: "h264",
        duration: 12.5,
        width: 1280,
        height: 720,
        timebase: 1.0 / 30.0
      ),
      events: AssetRef(
        path: "events.jsonl",
        type: .events,
        duration: 12.5,
        timebase: 1.0 / 1_000.0
      )
    )

    let edit = Edit(
      cuts: [Cut(start: 1.0, end: 2.0)],
      speedSegments: [SpeedSegment(start: 0.0, end: 4.0, rate: 1.5)],
      zoomSegments: [
        ZoomSegment(
          start: 0.2,
          end: 2.2,
          mode: .auto,
          scale: 1.2,
          targetPoint: TargetPoint(x: 0.4, y: 0.6),
          easing: "easeInOut"
        )
      ],
      cursorOverrides: [
        CursorOverride(
          start: 0.0,
          end: 1.5,
          hideCursor: true,
          disableSmoothing: false,
          cursorScale: 1.1
        )
      ],
      background: Background(
        type: .gradient,
        gradient: Background.Gradient(
          startColor: "#101010",
          endColor: "#3a3a3a",
          angle: 45.0
        ),
        padding: 24.0,
        cornerRadius: 12.0,
        shadow: Background.Shadow(
          radius: 8.0,
          x: 0.0,
          y: 2.0,
          color: "#000000",
          opacity: 0.4
        )
      ),
      motion: Motion(
        cursorStyle: .mellow,
        zoomStyle: .slow,
        spring: Motion.Spring(tension: 120.0, friction: 12.0, mass: 1.0)
      ),
      exportPresets: [
        ExportPreset(
          name: "1080p30",
          width: 1920,
          height: 1080,
          fps: 30.0,
          codec: .h264,
          bitrate: 8_000_000,
          quality: 0.7
        )
      ]
    )

    return ProjectModel(
      id: UUID(uuidString: "2D15A39C-5B3F-4AC6-9F33-2D2235B5D5C1")!,
      createdAt: Date(timeIntervalSince1970: 1_735_689_600),
      version: ProjectModel.currentVersion,
      appVersion: "0.1.0",
      assets: assets,
      edit: edit
    )
  }
}
