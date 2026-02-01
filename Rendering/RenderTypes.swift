import CoreGraphics
import CoreVideo
import Metal
import ProjectModel

public struct RenderColor: Equatable {
  public var red: Float
  public var green: Float
  public var blue: Float
  public var alpha: Float

  public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public init?(hex: String) {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard cleaned.count == 6 || cleaned.count == 8 else {
      return nil
    }
    guard let value = UInt64(cleaned, radix: 16) else {
      return nil
    }
    let r: UInt64
    let g: UInt64
    let b: UInt64
    let a: UInt64
    if cleaned.count == 8 {
      r = (value >> 24) & 0xFF
      g = (value >> 16) & 0xFF
      b = (value >> 8) & 0xFF
      a = value & 0xFF
    } else {
      r = (value >> 16) & 0xFF
      g = (value >> 8) & 0xFF
      b = value & 0xFF
      a = 0xFF
    }
    self.init(
      red: Float(r) / 255.0,
      green: Float(g) / 255.0,
      blue: Float(b) / 255.0,
      alpha: Float(a) / 255.0
    )
  }

  public func toSIMD4() -> SIMD4<Float> {
    SIMD4<Float>(red, green, blue, alpha)
  }

  public static let black = RenderColor(red: 0, green: 0, blue: 0, alpha: 1)
  public static let white = RenderColor(red: 1, green: 1, blue: 1, alpha: 1)
  public static let clear = RenderColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public enum RenderBackground {
  case color(RenderColor)
  case gradient(RenderGradient)
  case image(RenderBackgroundImage)
}

public struct RenderGradient {
  public var startColor: RenderColor
  public var endColor: RenderColor
  public var angleDegrees: Float

  public init(startColor: RenderColor, endColor: RenderColor, angleDegrees: Float = 0) {
    self.startColor = startColor
    self.endColor = endColor
    self.angleDegrees = angleDegrees
  }
}

public struct RenderBackgroundImage {
  public enum ContentMode {
    case aspectFill
    case aspectFit
    case stretch
  }

  public var texture: MTLTexture
  public var contentMode: ContentMode

  public init(texture: MTLTexture, contentMode: ContentMode = .aspectFill) {
    self.texture = texture
    self.contentMode = contentMode
  }
}

public struct RenderConfiguration {
  public var background: RenderBackground
  public var screenPadding: CGFloat
  public var screenCornerRadius: CGFloat
  public var screenEdgeSoftness: CGFloat
  public var screenShadow: RenderShadow?

  public init(
    background: RenderBackground = .color(.black),
    screenPadding: CGFloat = 0,
    screenCornerRadius: CGFloat = 0,
    screenEdgeSoftness: CGFloat = 1,
    screenShadow: RenderShadow? = nil
  ) {
    self.background = background
    self.screenPadding = screenPadding
    self.screenCornerRadius = screenCornerRadius
    self.screenEdgeSoftness = screenEdgeSoftness
    self.screenShadow = screenShadow
  }

  public func makeScreenLayer(
    sourceFrame: CVPixelBuffer,
    outputSize: CGSize,
    sourceRect: CGRect? = nil
  ) -> ScreenLayer {
    let width = CGFloat(CVPixelBufferGetWidth(sourceFrame))
    let height = CGFloat(CVPixelBufferGetHeight(sourceFrame))
    let screenFrame = RenderLayout.aspectFitRect(
      sourceSize: CGSize(width: width, height: height),
      in: outputSize,
      padding: screenPadding
    )
    return ScreenLayer(
      pixelBuffer: sourceFrame,
      sourceRect: sourceRect,
      frame: screenFrame,
      cornerRadius: screenCornerRadius,
      edgeSoftness: screenEdgeSoftness,
      shadow: screenShadow
    )
  }

  public static func fromProjectBackground(
    _ background: Background,
    image: RenderBackgroundImage? = nil,
    defaultColor: RenderColor = .black
  ) -> RenderConfiguration {
    let resolved = RenderBackground(background: background, image: image, defaultColor: defaultColor) ?? .color(defaultColor)
    return RenderConfiguration(
      background: resolved,
      screenPadding: CGFloat(background.padding ?? 0),
      screenCornerRadius: CGFloat(background.cornerRadius ?? 0),
      screenEdgeSoftness: 1,
      screenShadow: RenderShadow(shadow: background.shadow)
    )
  }
}

public struct RenderShadow {
  public var color: RenderColor
  public var offset: CGPoint
  public var radius: CGFloat
  public var opacity: Float

  public init(
    color: RenderColor = .black,
    offset: CGPoint = .zero,
    radius: CGFloat = 0,
    opacity: Float = 0.3
  ) {
    self.color = color
    self.offset = offset
    self.radius = radius
    self.opacity = opacity
  }
}

public struct ScreenLayer {
  public var pixelBuffer: CVPixelBuffer
  public var sourceRect: CGRect?
  public var frame: CGRect
  public var cornerRadius: CGFloat
  public var edgeSoftness: CGFloat
  public var shadow: RenderShadow?

  public init(
    pixelBuffer: CVPixelBuffer,
    sourceRect: CGRect? = nil,
    frame: CGRect,
    cornerRadius: CGFloat = 0,
    edgeSoftness: CGFloat = 1,
    shadow: RenderShadow? = nil
  ) {
    self.pixelBuffer = pixelBuffer
    self.sourceRect = sourceRect
    self.frame = frame
    self.cornerRadius = cornerRadius
    self.edgeSoftness = edgeSoftness
    self.shadow = shadow
  }
}

public struct CursorLayer {
  public var texture: MTLTexture
  public var size: CGSize
  public var position: CGPoint
  public var hotspot: CGPoint
  public var opacity: Float

  public init(
    texture: MTLTexture,
    size: CGSize,
    position: CGPoint,
    hotspot: CGPoint = .zero,
    opacity: Float = 1.0
  ) {
    self.texture = texture
    self.size = size
    self.position = position
    self.hotspot = hotspot
    self.opacity = opacity
  }
}

public struct RenderFrame {
  public var outputSize: CGSize
  public var background: RenderBackground
  public var screen: ScreenLayer
  public var cursor: CursorLayer?

  public init(
    outputSize: CGSize,
    background: RenderBackground,
    screen: ScreenLayer,
    cursor: CursorLayer? = nil
  ) {
    self.outputSize = outputSize
    self.background = background
    self.screen = screen
    self.cursor = cursor
  }
}

public struct RenderLayout {
  public static func aspectFitRect(
    sourceSize: CGSize,
    in container: CGSize,
    padding: CGFloat = 0
  ) -> CGRect {
    let insetWidth = max(container.width - padding * 2, 0)
    let insetHeight = max(container.height - padding * 2, 0)
    guard insetWidth > 0, insetHeight > 0, sourceSize.width > 0, sourceSize.height > 0 else {
      return CGRect(x: padding, y: padding, width: insetWidth, height: insetHeight)
    }
    let scale = min(insetWidth / sourceSize.width, insetHeight / sourceSize.height)
    let width = sourceSize.width * scale
    let height = sourceSize.height * scale
    let originX = (container.width - width) * 0.5
    let originY = (container.height - height) * 0.5
    return CGRect(x: originX, y: originY, width: width, height: height)
  }

  public static func aspectFillUVRect(
    sourceSize: CGSize,
    targetSize: CGSize
  ) -> CGRect {
    guard sourceSize.width > 0, sourceSize.height > 0, targetSize.width > 0, targetSize.height > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let sourceAspect = sourceSize.width / sourceSize.height
    let targetAspect = targetSize.width / targetSize.height
    if sourceAspect > targetAspect {
      let scale = targetAspect / sourceAspect
      let inset = (1 - scale) * 0.5
      return CGRect(x: inset, y: 0, width: scale, height: 1)
    }
    if sourceAspect < targetAspect {
      let scale = sourceAspect / targetAspect
      let inset = (1 - scale) * 0.5
      return CGRect(x: 0, y: inset, width: 1, height: scale)
    }
    return CGRect(x: 0, y: 0, width: 1, height: 1)
  }
}

public extension RenderBackground {
  init?(
    background: Background,
    image: RenderBackgroundImage? = nil,
    defaultColor: RenderColor = .black
  ) {
    switch background.type {
    case .color:
      if let colorHex = background.color, let color = RenderColor(hex: colorHex) {
        self = .color(color)
      } else {
        self = .color(defaultColor)
      }
    case .gradient:
      let start = background.gradient?.startColor.flatMap(RenderColor.init(hex:)) ?? defaultColor
      let end = background.gradient?.endColor.flatMap(RenderColor.init(hex:)) ?? defaultColor
      let angle = Float(background.gradient?.angle ?? 0)
      self = .gradient(RenderGradient(startColor: start, endColor: end, angleDegrees: angle))
    case .image:
      guard let image else {
        return nil
      }
      self = .image(image)
    }
  }
}

public extension RenderShadow {
  init?(shadow: Background.Shadow?) {
    guard let shadow else {
      return nil
    }
    let color = shadow.color.flatMap(RenderColor.init(hex:)) ?? .black
    let opacity = Float(shadow.opacity ?? 0.3)
    let offset = CGPoint(x: shadow.x ?? 0, y: shadow.y ?? 0)
    let radius = CGFloat(shadow.radius ?? 0)
    if opacity <= 0, radius <= 0 {
      return nil
    }
    self.init(color: color, offset: offset, radius: radius, opacity: opacity)
  }
}

public extension ScreenLayer {
  static func fromProjectBackground(
    _ background: Background,
    screenBuffer: CVPixelBuffer,
    outputSize: CGSize,
    sourceRect: CGRect? = nil
  ) -> ScreenLayer {
    let padding = CGFloat(background.padding ?? 0)
    let width = CGFloat(CVPixelBufferGetWidth(screenBuffer))
    let height = CGFloat(CVPixelBufferGetHeight(screenBuffer))
    let screenRect = RenderLayout.aspectFitRect(
      sourceSize: CGSize(width: width, height: height),
      in: outputSize,
      padding: padding
    )
    let cornerRadius = CGFloat(background.cornerRadius ?? 0)
    let shadow = RenderShadow(shadow: background.shadow)
    return ScreenLayer(
      pixelBuffer: screenBuffer,
      sourceRect: sourceRect,
      frame: screenRect,
      cornerRadius: cornerRadius,
      edgeSoftness: 1,
      shadow: shadow
    )
  }
}
