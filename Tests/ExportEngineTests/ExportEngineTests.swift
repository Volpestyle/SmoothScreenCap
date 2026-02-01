import AVFoundation
import CoreVideo
import CryptoKit
import ExportEngine
import ProjectModel
import Rendering
import TimeMapping
import XCTest

final class ExportEngineTests: XCTestCase {
  func testExportCapturesDeterministicHashes() async throws {
    let temp = try TemporaryDirectory()
    let sourceURL = temp.url.appendingPathComponent("source.mov")
    let outputURL = temp.url.appendingPathComponent("output.mp4")

    try await makeTestVideo(
      url: sourceURL,
      frameCount: 4,
      fps: 4,
      size: CGSize(width: 64, height: 64)
    )

    let timeMapping = TimeMapping(
      sourceDuration: 1.0,
      cuts: [],
      speedSegments: []
    )

    let renderer = HashingRenderer()
    let preset = ExportPreset(
      name: "test",
      width: 64,
      height: 64,
      fps: 4.0,
      codec: .h264,
      bitrate: 1_000_000,
      quality: 0.8
    )

    let request = ExportRequest(
      sourceVideoURL: sourceURL,
      systemAudioURL: nil,
      microphoneAudioURL: nil,
      timeMapping: timeMapping,
      outputURL: outputURL,
      preset: preset,
      renderer: renderer,
      temporaryDirectory: temp.url
    )

    let engine = ExportEngine()
    try await engine.export(request)

    XCTAssertEqual(renderer.hashes.count, 4)
    let expectedHashes = (0..<4).map { index in
      let buffer = try! PixelBufferFactory.make(width: 64, height: 64)
      let color = TestColor.forFrame(index)
      PixelBufferFactory.fill(buffer: buffer, color: color)
      return PixelBufferHasher.hash(buffer)
    }
    XCTAssertEqual(renderer.hashes, expectedHashes)

    for time in renderer.renderTimes {
      let expectedSource = timeMapping.sourceTime(for: time.outputTime) ?? -1
      XCTAssertEqual(time.sourceTime, expectedSource, accuracy: 0.0001)
    }
  }
}

private final class HashingRenderer: VideoFrameRenderer {
  private(set) var hashes: [String] = []
  private(set) var renderTimes: [RenderTime] = []

  func render(
    sourceFrame: CVPixelBuffer,
    destination: CVPixelBuffer,
    time: RenderTime,
    context: RenderContext
  ) throws {
    renderTimes.append(time)
    let color = TestColor.forFrame(time.frameIndex)
    PixelBufferFactory.fill(buffer: destination, color: color)
    hashes.append(PixelBufferHasher.hash(destination))
  }
}

private struct TestColor: Equatable {
  var r: UInt8
  var g: UInt8
  var b: UInt8
  var a: UInt8

  static func forFrame(_ index: Int) -> TestColor {
    let r = UInt8((index * 37) % 256)
    let g = UInt8((index * 59) % 256)
    let b = UInt8((index * 83) % 256)
    return TestColor(r: r, g: g, b: b, a: 255)
  }
}

private enum PixelBufferFactory {
  static func make(width: Int, height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferBytesPerRowAlignmentKey as String: width * 4
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &buffer
    )
    if status != kCVReturnSuccess || buffer == nil {
      throw NSError(domain: "ExportEngineTests", code: Int(status))
    }
    return buffer!
  }

  static func fill(buffer: CVPixelBuffer, color: TestColor) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)

    for row in 0..<height {
      let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
      var pixel = rowPtr.assumingMemoryBound(to: UInt8.self)
      for _ in 0..<width {
        pixel[0] = color.b
        pixel[1] = color.g
        pixel[2] = color.r
        pixel[3] = color.a
        pixel = pixel.advanced(by: 4)
      }
      let padding = bytesPerRow - width * 4
      if padding > 0 {
        memset(rowPtr.advanced(by: width * 4), 0, padding)
      }
    }
  }
}

private enum PixelBufferHasher {
  static func hash(_ buffer: CVPixelBuffer) -> String {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      return ""
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let count = bytesPerRow * height
    let data = Data(bytes: baseAddress, count: count)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

private struct TemporaryDirectory {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
    let name = "ssc-tests-\(UUID().uuidString)"
    let url = base.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    self.url = url
  }
}

private func makeTestVideo(url: URL, frameCount: Int, fps: Int, size: CGSize) async throws {
  if FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.removeItem(at: url)
  }
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
  let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(size.width),
    AVVideoHeightKey: Int(size.height)
  ]
  let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
  input.expectsMediaDataInRealTime = false

  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: Int(size.width),
      kCVPixelBufferHeightKey as String: Int(size.height),
      kCVPixelBufferBytesPerRowAlignmentKey as String: Int(size.width) * 4
    ]
  )

  guard writer.canAdd(input) else {
    throw NSError(domain: "ExportEngineTests", code: 1)
  }
  writer.add(input)
  writer.startWriting()
  writer.startSession(atSourceTime: .zero)

  for index in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.001)
    }
    let buffer = try PixelBufferFactory.make(width: Int(size.width), height: Int(size.height))
    PixelBufferFactory.fill(buffer: buffer, color: TestColor.forFrame(index))
    let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
    adaptor.append(buffer, withPresentationTime: time)
  }

  input.markAsFinished()
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    writer.finishWriting {
      if let error = writer.error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: ())
      }
    }
  }
}
