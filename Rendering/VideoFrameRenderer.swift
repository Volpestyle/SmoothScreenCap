import CoreGraphics
import CoreVideo

public struct RenderTime: Equatable {
  public var frameIndex: Int
  public var outputTime: Double
  public var sourceTime: Double
  public var fps: Double

  public init(frameIndex: Int, outputTime: Double, sourceTime: Double, fps: Double) {
    self.frameIndex = frameIndex
    self.outputTime = outputTime
    self.sourceTime = sourceTime
    self.fps = fps
  }
}

public struct RenderContext: Equatable {
  public var outputSize: CGSize
  public var pixelFormat: OSType

  public init(outputSize: CGSize, pixelFormat: OSType) {
    self.outputSize = outputSize
    self.pixelFormat = pixelFormat
  }
}

public protocol VideoFrameRenderer {
  func render(
    sourceFrame: CVPixelBuffer,
    destination: CVPixelBuffer,
    time: RenderTime,
    context: RenderContext
  ) throws
}
