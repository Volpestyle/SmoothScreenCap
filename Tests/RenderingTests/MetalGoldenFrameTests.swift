import CoreVideo
import CryptoKit
import Metal
import Rendering
import XCTest

final class MetalGoldenFrameTests: XCTestCase {
  func testMetalBackgroundAndScreenGolden() throws {
    let renderer = try makeRenderer()
    let outputSize = CGSize(width: 64, height: 64)
    let source = try makePixelBuffer(width: 32, height: 32, color: RenderColor(red: 0.2, green: 0.6, blue: 0.9))
    let config = RenderConfiguration(
      background: .color(RenderColor(red: 0.08, green: 0.08, blue: 0.08)),
      screenPadding: 8,
      screenCornerRadius: 4,
      screenEdgeSoftness: 1,
      screenShadow: nil
    )
    let screen = config.makeScreenLayer(sourceFrame: source, outputSize: outputSize)
    let frame = RenderFrame(
      outputSize: outputSize,
      background: config.background,
      screen: screen,
      cursor: nil
    )

    let output = try renderer.render(frame: frame, waitUntilCompleted: true)
    let hash = hashPixelBuffer(output)
    XCTAssertEqual(hash, expectedGoldenHash)
  }
}

private let expectedGoldenHash = "7609caa3026a1e219bd0667bf0c3963d8f05fd6ef684f85e173c1ef0cdcdfa0d"

private func makeRenderer() throws -> MetalRenderer {
  guard let device = MTLCreateSystemDefaultDevice() else {
    throw NSError(domain: "RenderingTests", code: 0)
  }
  let shaderURL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Rendering/Shaders/RendererShaders.metal")
  let source = try String(contentsOf: shaderURL)
  let library = try device.makeLibrary(source: source, options: nil)
  return try MetalRenderer(device: device, shaderLibrary: library)
}

private func makePixelBuffer(width: Int, height: Int, color: RenderColor) throws -> CVPixelBuffer {
  var buffer: CVPixelBuffer?
  let attrs: [String: Any] = [
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
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
    throw NSError(domain: "RenderingTests", code: Int(status))
  }
  guard let pixelBuffer = buffer else {
    throw NSError(domain: "RenderingTests", code: 1)
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

  guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    return pixelBuffer
  }
  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let widthBytes = width * 4
  let height = CVPixelBufferGetHeight(pixelBuffer)

  let r = UInt8(max(0, min(255, Int(color.red * 255))))
  let g = UInt8(max(0, min(255, Int(color.green * 255))))
  let b = UInt8(max(0, min(255, Int(color.blue * 255))))
  let a: UInt8 = 255

  for row in 0..<height {
    let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
    var pixel = rowPtr.assumingMemoryBound(to: UInt8.self)
    for _ in 0..<width {
      pixel[0] = b
      pixel[1] = g
      pixel[2] = r
      pixel[3] = a
      pixel = pixel.advanced(by: 4)
    }
    let padding = bytesPerRow - widthBytes
    if padding > 0 {
      memset(rowPtr.advanced(by: widthBytes), 0, padding)
    }
  }

  return pixelBuffer
}

private func hashPixelBuffer(_ buffer: CVPixelBuffer) -> String {
  CVPixelBufferLockBaseAddress(buffer, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

  guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
    return ""
  }
  let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
  let height = CVPixelBufferGetHeight(buffer)
  let data = Data(bytes: baseAddress, count: bytesPerRow * height)
  let digest = SHA256.hash(data: data)
  return digest.map { String(format: "%02x", $0) }.joined()
}
