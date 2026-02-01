import XCTest
import AutoZoom

final class AutoZoomTests: XCTestCase {
  func testMergesIntervals() {
    let clicks = [
      AutoZoom.ClickEvent(time: 1.0, location: .init(x: 100, y: 100)),
      AutoZoom.ClickEvent(time: 1.4, location: .init(x: 120, y: 120))
    ]

    let segments = AutoZoom.generateSegments(
      clicks: clicks,
      sourceSize: .init(width: 1920, height: 1080),
      outputAspectRatio: 16.0 / 9.0,
      duration: 5.0,
      config: .init(preRoll: 0.2, postRoll: 0.5, settleTime: 0.0)
    )

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].start, 0.8, accuracy: 0.0001)
    XCTAssertEqual(segments[0].end, 1.9, accuracy: 0.0001)
  }

  func testLastClickFocus() {
    let clicks = [
      AutoZoom.ClickEvent(time: 1.0, location: .init(x: 100, y: 100)),
      AutoZoom.ClickEvent(time: 1.2, location: .init(x: 300, y: 250))
    ]

    let segments = AutoZoom.generateSegments(
      clicks: clicks,
      sourceSize: .init(width: 800, height: 600),
      outputAspectRatio: 4.0 / 3.0,
      duration: 3.0,
      config: .init(preRoll: 0.1, postRoll: 0.3, settleTime: 0.0, focusMode: .lastClick)
    )

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].targetPoint?.x ?? -1, 300, accuracy: 0.0001)
    XCTAssertEqual(segments[0].targetPoint?.y ?? -1, 250, accuracy: 0.0001)
  }

  func testTargetRectClampsWithinBounds() {
    let clicks = [
      AutoZoom.ClickEvent(time: 0.5, location: .init(x: 950, y: 250))
    ]

    let segments = AutoZoom.generateSegments(
      clicks: clicks,
      sourceSize: .init(width: 1000, height: 500),
      outputAspectRatio: 1.0,
      duration: 2.0,
      config: .init(preRoll: 0.1, postRoll: 0.2, settleTime: 0.0, padding: 0, defaultZoom: 2.0)
    )

    XCTAssertEqual(segments.count, 1)
    guard let rect = segments[0].targetRect else {
      XCTFail("Expected target rect")
      return
    }

    XCTAssertLessThanOrEqual(rect.x + rect.width, 1000.0 + 0.0001)
    XCTAssertGreaterThanOrEqual(rect.x, 0.0 - 0.0001)
    XCTAssertLessThanOrEqual(rect.y + rect.height, 500.0 + 0.0001)
    XCTAssertGreaterThanOrEqual(rect.y, 0.0 - 0.0001)
  }
}
