import XCTest
import EventLog

final class EventLogTests: XCTestCase {
  func testJSONLRoundTrip() throws {
    let entries = [
      EventLogEntry(
        time: 0.1,
        mouse: .init(
          action: .move,
          location: .init(x: 120, y: 240),
          globalLocation: .init(x: 520, y: 640)
        )
      ),
      EventLogEntry(
        time: 0.2,
        mouse: .init(
          action: .down,
          button: .left,
          location: .init(x: 140, y: 260),
          globalLocation: .init(x: 540, y: 660)
        )
      ),
      EventLogEntry(
        time: 0.3,
        scroll: .init(deltaX: 0, deltaY: -120)
      ),
      EventLogEntry(
        time: 0.4,
        key: .init(action: .down, keyCode: nil, isRepeat: false, modifiers: ["cmd"])
      )
    ]

    let data = try EventLogJSONL.encode(entries)
    let decoded = try EventLogJSONL.decode(data)

    XCTAssertEqual(decoded, entries)
  }
}
