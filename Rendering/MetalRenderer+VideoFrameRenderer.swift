import CoreVideo

extension MetalRenderer: VideoFrameRenderer {
  public func render(
    sourceFrame: CVPixelBuffer,
    destination: CVPixelBuffer,
    time: RenderTime,
    context: RenderContext
  ) throws {
    let outputSize = CGSize(
      width: CVPixelBufferGetWidth(destination),
      height: CVPixelBufferGetHeight(destination)
    )
    let sourceRect = screenSourceRectProvider?(time, context)
    let screenLayer = renderConfiguration.makeScreenLayer(
      sourceFrame: sourceFrame,
      outputSize: outputSize,
      sourceRect: sourceRect
    )
    let cursor = cursorProvider?(time, context)
    let frame = RenderFrame(
      outputSize: outputSize,
      background: renderConfiguration.background,
      screen: screenLayer,
      cursor: cursor
    )

    // Convert destination CVPixelBuffer to MTLTexture and render
    let destTexture = try makeTexture(from: destination)
    try render(frame: frame, into: destTexture, waitUntilCompleted: true)
  }
}
