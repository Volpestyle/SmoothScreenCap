import Foundation
import CoreGraphics
import CoreVideo
import Metal
import MetalKit

public final class MetalRenderer {
  private static let verticesPerQuad = 6
  private static let maxQuadsPerFrame = 32
  private static let inFlightBufferCount = 3

  public struct Configuration: Equatable {
    public var pixelFormat: MTLPixelFormat

    public init(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
      self.pixelFormat = pixelFormat
    }
  }

  private struct Vertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
  }

  private struct GradientUniforms {
    var startColor: SIMD4<Float>
    var endColor: SIMD4<Float>
    var direction: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
  }

  private struct TextureUniforms {
    var opacity: Float
    var padding: SIMD3<Float> = .zero
  }

  private struct RoundedRectUniforms {
    var size: SIMD2<Float>
    var cornerRadius: Float
    var edgeSoftness: Float
  }

  private struct ColorUniforms {
    var color: SIMD4<Float>
  }

  private struct ClickRippleUniforms {
    var size: SIMD2<Float>
    var progress: Float
    var color: SIMD4<Float>
    var maxRadius: Float
    var padding: Float = 0
  }

  public let device: MTLDevice
  public var renderConfiguration: RenderConfiguration
  public var cursorProvider: ((RenderTime, RenderContext) -> CursorLayer?)?
  public var clickHighlightProvider: ((RenderTime, RenderContext) -> ClickHighlight?)?
  public var screenSourceRectProvider: ((RenderTime, RenderContext) -> CGRect?)?

  private let commandQueue: MTLCommandQueue
  private let backgroundPipeline: MTLRenderPipelineState
  private let texturedPipeline: MTLRenderPipelineState
  private let roundedColorPipeline: MTLRenderPipelineState
  private let clickRipplePipeline: MTLRenderPipelineState
  private let samplerState: MTLSamplerState
  private let vertexBuffer: MTLBuffer
  private let textureLoader: MTKTextureLoader
  private let inFlightSemaphore = DispatchSemaphore(value: MetalRenderer.inFlightBufferCount)
  private let frameVertexCapacity: Int
  private var frameVertexOffset: Int = 0
  private var frameBaseOffset: Int = 0
  private var frameIndex: Int = 0

  private var textureCache: CVMetalTextureCache
  private var pixelBufferPool: CVPixelBufferPool?
  private var poolSize: CGSize = .zero
  private var poolPixelFormat: OSType = 0

  public init(
    device: MTLDevice? = MTLCreateSystemDefaultDevice(),
    configuration: Configuration = Configuration(),
    renderConfiguration: RenderConfiguration = RenderConfiguration(),
    shaderLibrary: MTLLibrary? = nil
  ) throws {
    guard let device else {
      throw RenderingError.deviceUnavailable
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw RenderingError.deviceUnavailable
    }
    self.device = device
    self.renderConfiguration = renderConfiguration
    self.commandQueue = commandQueue
    self.textureLoader = MTKTextureLoader(device: device)

    var cache: CVMetalTextureCache?
    let cacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    guard cacheStatus == kCVReturnSuccess, let createdCache = cache else {
      throw RenderingError.textureCreationFailed
    }
    self.textureCache = createdCache

    let library: MTLLibrary
    if let shaderLibrary {
      library = shaderLibrary
    } else {
      do {
        library = try device.makeDefaultLibrary(bundle: .module)
      } catch {
        throw RenderingError.shaderLibraryNotFound
      }
    }
    guard
      let vertexFunction = library.makeFunction(name: "vertexQuad"),
      let backgroundFunction = library.makeFunction(name: "fragmentBackground"),
      let texturedFunction = library.makeFunction(name: "fragmentTexturedRounded"),
      let roundedColorFunction = library.makeFunction(name: "fragmentSolidRounded"),
      let clickRippleFunction = library.makeFunction(name: "fragmentClickRipple")
    else {
      throw RenderingError.shaderLibraryNotFound
    }

    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float2
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.attributes[1].format = .float2
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride

    self.backgroundPipeline = try MetalRenderer.makePipelineState(
      device: device,
      vertexFunction: vertexFunction,
      fragmentFunction: backgroundFunction,
      vertexDescriptor: vertexDescriptor,
      pixelFormat: configuration.pixelFormat
    )

    self.texturedPipeline = try MetalRenderer.makePipelineState(
      device: device,
      vertexFunction: vertexFunction,
      fragmentFunction: texturedFunction,
      vertexDescriptor: vertexDescriptor,
      pixelFormat: configuration.pixelFormat
    )

    self.roundedColorPipeline = try MetalRenderer.makePipelineState(
      device: device,
      vertexFunction: vertexFunction,
      fragmentFunction: roundedColorFunction,
      vertexDescriptor: vertexDescriptor,
      pixelFormat: configuration.pixelFormat
    )

    self.clickRipplePipeline = try MetalRenderer.makePipelineState(
      device: device,
      vertexFunction: vertexFunction,
      fragmentFunction: clickRippleFunction,
      vertexDescriptor: vertexDescriptor,
      pixelFormat: configuration.pixelFormat
    )

    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
      throw RenderingError.deviceUnavailable
    }
    self.samplerState = samplerState

    let bytesPerQuad = MemoryLayout<Vertex>.stride * MetalRenderer.verticesPerQuad
    let vertexBufferLength = bytesPerQuad
      * MetalRenderer.maxQuadsPerFrame
      * MetalRenderer.inFlightBufferCount
    guard let vertexBuffer = device.makeBuffer(length: vertexBufferLength, options: [.storageModeShared]) else {
      throw RenderingError.deviceUnavailable
    }
    self.vertexBuffer = vertexBuffer
    self.frameVertexCapacity = bytesPerQuad * MetalRenderer.maxQuadsPerFrame
  }

  public func makeTexture(from image: CGImage, srgb: Bool = true) throws -> MTLTexture {
    let options: [MTKTextureLoader.Option: Any] = [
      .SRGB: srgb
    ]
    return try textureLoader.newTexture(cgImage: image, options: options)
  }

  public func render(frame: RenderFrame, waitUntilCompleted: Bool = true) throws -> CVPixelBuffer {
    let pixelBuffer = try makePixelBuffer(size: frame.outputSize)
    let texture = try makeTexture(from: pixelBuffer)
    try render(frame: frame, into: texture, waitUntilCompleted: waitUntilCompleted)
    return pixelBuffer
  }

  public func render(
    frame: RenderFrame,
    into texture: MTLTexture,
    waitUntilCompleted: Bool = false
  ) throws {
    let outputWidth = Int(frame.outputSize.width.rounded())
    let outputHeight = Int(frame.outputSize.height.rounded())
    guard outputWidth > 0, outputHeight > 0 else {
      throw RenderingError.invalidOutputSize
    }
    guard texture.width == outputWidth, texture.height == outputHeight else {
      throw RenderingError.invalidOutputSize
    }

    beginFrame()
    var didCommit = false
    defer {
      if !didCommit {
        inFlightSemaphore.signal()
      }
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw RenderingError.deviceUnavailable
    }
    commandBuffer.addCompletedHandler { [weak self] _ in
      self?.inFlightSemaphore.signal()
    }
    let renderPass = MTLRenderPassDescriptor()
    renderPass.colorAttachments[0].texture = texture
    renderPass.colorAttachments[0].loadAction = .clear
    renderPass.colorAttachments[0].storeAction = .store
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
      throw RenderingError.deviceUnavailable
    }

    do {
      try encode(frame: frame, encoder: encoder)
      encoder.endEncoding()
    } catch {
      encoder.endEncoding()
      throw error
    }
    commandBuffer.commit()
    didCommit = true
    if waitUntilCompleted {
      commandBuffer.waitUntilCompleted()
    }
  }

  public func render(
    frame: RenderFrame,
    in view: MTKView,
    waitUntilCompleted: Bool = false
  ) throws {
    guard let drawable = view.currentDrawable,
          let renderPass = view.currentRenderPassDescriptor else {
      return
    }
    beginFrame()
    var didCommit = false
    defer {
      if !didCommit {
        inFlightSemaphore.signal()
      }
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw RenderingError.deviceUnavailable
    }
    commandBuffer.addCompletedHandler { [weak self] _ in
      self?.inFlightSemaphore.signal()
    }
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
      throw RenderingError.deviceUnavailable
    }

    try encode(frame: frame, encoder: encoder)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    didCommit = true
    if waitUntilCompleted {
      commandBuffer.waitUntilCompleted()
    }
  }

  private func drawBackground(frame: RenderFrame, encoder: MTLRenderCommandEncoder) throws {
    let outputRect = CGRect(origin: .zero, size: frame.outputSize)
    switch frame.background {
    case .color(let color):
      encoder.setRenderPipelineState(backgroundPipeline)
      var uniforms = GradientUniforms(
        startColor: color.toSIMD4(),
        endColor: color.toSIMD4(),
        direction: SIMD2<Float>(1, 0)
      )
      drawQuad(
        rect: outputRect,
        outputSize: frame.outputSize,
        uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        encoder: encoder
      )
      encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    case .gradient(let gradient):
      encoder.setRenderPipelineState(backgroundPipeline)
      let radians = gradient.angleDegrees * Float.pi / 180
      let direction = SIMD2<Float>(cos(radians), sin(radians))
      var uniforms = GradientUniforms(
        startColor: gradient.startColor.toSIMD4(),
        endColor: gradient.endColor.toSIMD4(),
        direction: direction
      )
      drawQuad(
        rect: outputRect,
        outputSize: frame.outputSize,
        uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        encoder: encoder
      )
      encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    case .image(let image):
      encoder.setRenderPipelineState(texturedPipeline)
      encoder.setFragmentTexture(image.texture, index: 0)
      encoder.setFragmentSamplerState(samplerState, index: 0)

      let imageSize = CGSize(width: image.texture.width, height: image.texture.height)
      let rect: CGRect
      let uvRect: CGRect
      switch image.contentMode {
      case .stretch:
        rect = outputRect
        uvRect = CGRect(x: 0, y: 0, width: 1, height: 1)
      case .aspectFit:
        rect = RenderLayout.aspectFitRect(sourceSize: imageSize, in: frame.outputSize)
        uvRect = CGRect(x: 0, y: 0, width: 1, height: 1)
      case .aspectFill:
        rect = outputRect
        uvRect = RenderLayout.aspectFillUVRect(sourceSize: imageSize, targetSize: frame.outputSize)
      }

      var textureUniforms = TextureUniforms(opacity: 1)
      var roundUniforms = RoundedRectUniforms(
        size: SIMD2<Float>(Float(rect.width), Float(rect.height)),
        cornerRadius: 0,
        edgeSoftness: 0
      )
      drawQuad(rect: rect, outputSize: frame.outputSize, uvRect: uvRect, encoder: encoder)
      encoder.setFragmentBytes(&textureUniforms, length: MemoryLayout<TextureUniforms>.stride, index: 0)
      encoder.setFragmentBytes(&roundUniforms, length: MemoryLayout<RoundedRectUniforms>.stride, index: 1)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
  }

  private func drawScreen(frame: RenderFrame, encoder: MTLRenderCommandEncoder) throws {
    let screen = frame.screen
    if let shadow = screen.shadow {
      try drawShadow(screen: screen, shadow: shadow, frame: frame, encoder: encoder)
    }

    let texture = try makeTexture(from: screen.pixelBuffer)
    encoder.setRenderPipelineState(texturedPipeline)
    encoder.setFragmentTexture(texture, index: 0)
    encoder.setFragmentSamplerState(samplerState, index: 0)

    let uvRect = screenUVRect(for: screen, texture: texture)
    var textureUniforms = TextureUniforms(opacity: 1)
    var roundUniforms = RoundedRectUniforms(
      size: SIMD2<Float>(Float(screen.frame.width), Float(screen.frame.height)),
      cornerRadius: Float(screen.cornerRadius),
      edgeSoftness: max(Float(screen.edgeSoftness), 0)
    )
    drawQuad(rect: screen.frame, outputSize: frame.outputSize, uvRect: uvRect, encoder: encoder)
    encoder.setFragmentBytes(&textureUniforms, length: MemoryLayout<TextureUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&roundUniforms, length: MemoryLayout<RoundedRectUniforms>.stride, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }

  private func drawShadow(
    screen: ScreenLayer,
    shadow: RenderShadow,
    frame: RenderFrame,
    encoder: MTLRenderCommandEncoder
  ) throws {
    let opacity = clamp01(shadow.opacity)
    guard opacity > 0 else {
      return
    }
    let radius = max(shadow.radius, 0)
    let shadowRect = screen.frame
      .insetBy(dx: -radius, dy: -radius)
      .offsetBy(dx: shadow.offset.x, dy: shadow.offset.y)

    let color = RenderColor(
      red: shadow.color.red,
      green: shadow.color.green,
      blue: shadow.color.blue,
      alpha: shadow.color.alpha * opacity
    )
    encoder.setRenderPipelineState(roundedColorPipeline)
    var colorUniforms = ColorUniforms(color: color.toSIMD4())
    let softness = max(Float(radius) * 0.5, 1)
    var roundUniforms = RoundedRectUniforms(
      size: SIMD2<Float>(Float(shadowRect.width), Float(shadowRect.height)),
      cornerRadius: Float(screen.cornerRadius + radius),
      edgeSoftness: softness
    )
    drawQuad(rect: shadowRect, outputSize: frame.outputSize, uvRect: CGRect(x: 0, y: 0, width: 1, height: 1), encoder: encoder)
    encoder.setFragmentBytes(&colorUniforms, length: MemoryLayout<ColorUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&roundUniforms, length: MemoryLayout<RoundedRectUniforms>.stride, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }

  private func drawCursor(frame: RenderFrame, encoder: MTLRenderCommandEncoder) throws {
    guard let cursor = frame.cursor else {
      return
    }
    let origin = CGPoint(
      x: cursor.position.x - cursor.hotspot.x,
      y: cursor.position.y - cursor.hotspot.y
    )
    let rect = CGRect(origin: origin, size: cursor.size)
    guard rect.width > 0, rect.height > 0 else {
      return
    }

    encoder.setRenderPipelineState(texturedPipeline)
    encoder.setFragmentTexture(cursor.texture, index: 0)
    encoder.setFragmentSamplerState(samplerState, index: 0)

    var textureUniforms = TextureUniforms(opacity: clamp01(cursor.opacity))
    var roundUniforms = RoundedRectUniforms(
      size: SIMD2<Float>(Float(rect.width), Float(rect.height)),
      cornerRadius: 0,
      edgeSoftness: 0
    )
    drawQuad(rect: rect, outputSize: frame.outputSize, uvRect: CGRect(x: 0, y: 0, width: 1, height: 1), encoder: encoder)
    encoder.setFragmentBytes(&textureUniforms, length: MemoryLayout<TextureUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&roundUniforms, length: MemoryLayout<RoundedRectUniforms>.stride, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }

  private func drawClickHighlight(frame: RenderFrame, encoder: MTLRenderCommandEncoder) throws {
    guard let highlight = frame.clickHighlight,
          highlight.enabled,
          highlight.progress < 1.0 else {
      return
    }

    // Calculate the rect for the ripple effect
    let rippleSize = highlight.maxRadius * 2
    let rect = CGRect(
      x: highlight.position.x - highlight.maxRadius,
      y: highlight.position.y - highlight.maxRadius,
      width: rippleSize,
      height: rippleSize
    )

    encoder.setRenderPipelineState(clickRipplePipeline)

    var uniforms = ClickRippleUniforms(
      size: SIMD2<Float>(Float(rect.width), Float(rect.height)),
      progress: highlight.progress,
      color: highlight.color.toSIMD4(),
      maxRadius: Float(highlight.maxRadius)
    )

    drawQuad(
      rect: rect,
      outputSize: frame.outputSize,
      uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
      encoder: encoder
    )
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ClickRippleUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }

  private func makePixelBuffer(size: CGSize) throws -> CVPixelBuffer {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0 else {
      throw RenderingError.invalidOutputSize
    }
    if pixelBufferPool == nil || poolSize != size || poolPixelFormat != kCVPixelFormatType_32BGRA {
      pixelBufferPool = try createPixelBufferPool(width: width, height: height)
      poolSize = size
      poolPixelFormat = kCVPixelFormatType_32BGRA
    }
    guard let pool = pixelBufferPool else {
      throw RenderingError.pixelBufferPoolCreationFailed
    }
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
    guard status == kCVReturnSuccess, let created = pixelBuffer else {
      throw RenderingError.pixelBufferPoolCreationFailed
    }
    return created
  }

  private func createPixelBufferPool(width: Int, height: Int) throws -> CVPixelBufferPool {
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]
    var pool: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    guard status == kCVReturnSuccess, let created = pool else {
      throw RenderingError.pixelBufferPoolCreationFailed
    }
    return created
  }

  public func makeTexture(from pixelBuffer: CVPixelBuffer) throws -> MTLTexture {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard format == kCVPixelFormatType_32BGRA else {
      throw RenderingError.textureCreationFailed
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var cvTexture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      nil,
      textureCache,
      pixelBuffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &cvTexture
    )
    guard status == kCVReturnSuccess, let cvTexture else {
      throw RenderingError.textureCreationFailed
    }
    guard let texture = CVMetalTextureGetTexture(cvTexture) else {
      throw RenderingError.textureCreationFailed
    }
    return texture
  }

  private static func makePipelineState(
    device: MTLDevice,
    vertexFunction: MTLFunction,
    fragmentFunction: MTLFunction,
    vertexDescriptor: MTLVertexDescriptor,
    pixelFormat: MTLPixelFormat
  ) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.vertexDescriptor = vertexDescriptor
    descriptor.colorAttachments[0].pixelFormat = pixelFormat
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

    do {
      return try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
      throw RenderingError.pipelineCreationFailed(String(describing: error))
    }
  }

  private func drawQuad(
    rect: CGRect,
    outputSize: CGSize,
    uvRect: CGRect,
    encoder: MTLRenderCommandEncoder
  ) {
    let vertices = quadVertices(rect: rect, outputSize: outputSize, uvRect: uvRect)
    let length = vertices.count * MemoryLayout<Vertex>.stride
    precondition(length == MemoryLayout<Vertex>.stride * MetalRenderer.verticesPerQuad)
    precondition(frameVertexOffset + length <= frameVertexCapacity, "Exceeded max quads per frame.")
    vertices.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      let destination = vertexBuffer.contents().advanced(by: frameBaseOffset + frameVertexOffset)
      destination.copyMemory(from: baseAddress, byteCount: length)
    }
    encoder.setVertexBuffer(vertexBuffer, offset: frameBaseOffset + frameVertexOffset, index: 0)
    frameVertexOffset += length
  }

  private func beginFrame() {
    inFlightSemaphore.wait()
    let inFlightIndex = frameIndex % MetalRenderer.inFlightBufferCount
    frameIndex += 1
    frameBaseOffset = inFlightIndex * frameVertexCapacity
    frameVertexOffset = 0
  }

  private func quadVertices(rect: CGRect, outputSize: CGSize, uvRect: CGRect) -> [Vertex] {
    let width = max(outputSize.width, 1)
    let height = max(outputSize.height, 1)

    let x0 = rect.minX
    let y0 = rect.minY
    let x1 = rect.maxX
    let y1 = rect.maxY

    let clipX0 = Float((x0 / width) * 2 - 1)
    let clipX1 = Float((x1 / width) * 2 - 1)
    let clipY0 = Float(1 - (y0 / height) * 2)
    let clipY1 = Float(1 - (y1 / height) * 2)

    let u0 = Float(uvRect.minX)
    let v0 = Float(uvRect.minY)
    let u1 = Float(uvRect.maxX)
    let v1 = Float(uvRect.maxY)

    let topLeft = Vertex(position: SIMD2<Float>(clipX0, clipY0), uv: SIMD2<Float>(u0, v0))
    let bottomLeft = Vertex(position: SIMD2<Float>(clipX0, clipY1), uv: SIMD2<Float>(u0, v1))
    let bottomRight = Vertex(position: SIMD2<Float>(clipX1, clipY1), uv: SIMD2<Float>(u1, v1))
    let topRight = Vertex(position: SIMD2<Float>(clipX1, clipY0), uv: SIMD2<Float>(u1, v0))

    return [
      topLeft, bottomLeft, bottomRight,
      topLeft, bottomRight, topRight
    ]
  }

  private func screenUVRect(for screen: ScreenLayer, texture: MTLTexture) -> CGRect {
    guard let sourceRect = screen.sourceRect else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let width = CGFloat(texture.width)
    let height = CGFloat(texture.height)
    guard width > 0, height > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let clamped = sourceRect
      .intersection(CGRect(x: 0, y: 0, width: width, height: height))
    if clamped.isNull || clamped.width <= 0 || clamped.height <= 0 {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let u0 = clamped.minX / width
    let v0 = clamped.minY / height
    let u1 = clamped.maxX / width
    let v1 = clamped.maxY / height
    return CGRect(x: u0, y: v0, width: u1 - u0, height: v1 - v0)
  }

  private func clamp01(_ value: Float) -> Float {
    min(max(value, 0), 1)
  }

  private func encode(frame: RenderFrame, encoder: MTLRenderCommandEncoder) throws {
    try drawBackground(frame: frame, encoder: encoder)
    try drawScreen(frame: frame, encoder: encoder)
    try drawClickHighlight(frame: frame, encoder: encoder)
    try drawCursor(frame: frame, encoder: encoder)
  }
}
