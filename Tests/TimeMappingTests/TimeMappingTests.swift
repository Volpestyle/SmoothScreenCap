import XCTest
import TimeMapping
import ProjectModel

final class TimeMappingTests: XCTestCase {
  func testIdentityMapping() {
    let mapping = TimeMapping(
      sourceDuration: 10,
      cuts: [],
      speedSegments: []
    )

    XCTAssertEqual(mapping.outputDuration, 10, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 0), 0, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 5), 5, accuracy: 0.0001)
    XCTAssertEqual(mapping.sourceTime(for: 5), 5, accuracy: 0.0001)
  }

  func testCutsRemoveTime() {
    let mapping = TimeMapping(
      sourceDuration: 10,
      cuts: [Cut(start: 2, end: 4)],
      speedSegments: []
    )

    XCTAssertNil(mapping.outputTime(for: 3))
    XCTAssertEqual(mapping.outputTime(for: 1), 1, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 5), 3, accuracy: 0.0001)
    XCTAssertEqual(mapping.sourceTime(for: 3), 5, accuracy: 0.0001)
  }

  func testSpeedSegmentsScaleTime() {
    let mapping = TimeMapping(
      sourceDuration: 10,
      cuts: [],
      speedSegments: [SpeedSegment(start: 2, end: 6, rate: 2.0)]
    )

    XCTAssertEqual(mapping.outputDuration, 8, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 1), 1, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 3), 2.5, accuracy: 0.0001)
    XCTAssertEqual(mapping.outputTime(for: 8), 6, accuracy: 0.0001)
    XCTAssertEqual(mapping.sourceTime(for: 2.5), 3, accuracy: 0.0001)
  }

  func testInvertibilityWithinSegments() {
    let mapping = TimeMapping(
      sourceDuration: 12,
      cuts: [Cut(start: 4, end: 5)],
      speedSegments: [SpeedSegment(start: 6, end: 10, rate: 1.5)]
    )

    let samples: [Double] = [0, 1, 3.5, 5, 6.2, 9.8, 11.9]
    for source in samples {
      guard let output = mapping.outputTime(for: source) else { continue }
      guard let roundTrip = mapping.sourceTime(for: output) else {
        XCTFail("Expected output time \(output) to map back to source time")
        continue
      }
      XCTAssertEqual(roundTrip, source, accuracy: 0.0001)
    }
  }
}
