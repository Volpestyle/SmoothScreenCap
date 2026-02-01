import Foundation

public struct ProjectModel: Codable, Equatable {
  public static let currentVersion = "1"
  public static let projectFilename = "project.json"

  public var id: UUID
  public var createdAt: Date
  public var version: String
  public var appVersion: String?
  public var assets: Assets
  public var edit: Edit

  public init(
    id: UUID,
    createdAt: Date,
    version: String,
    appVersion: String? = nil,
    assets: Assets,
    edit: Edit
  ) {
    self.id = id
    self.createdAt = createdAt
    self.version = version
    self.appVersion = appVersion
    self.assets = assets
    self.edit = edit
  }

  public func encodedJSON(prettyPrinted: Bool = false) throws -> Data {
    let encoder = ProjectModelJSON.encoder(prettyPrinted: prettyPrinted)
    return try encoder.encode(self)
  }

  public static func decodeJSON(_ data: Data) throws -> ProjectModel {
    let decoder = ProjectModelJSON.decoder()
    return try decoder.decode(ProjectModel.self, from: data)
  }
}

public struct Assets: Codable, Equatable {
  public var screen: AssetRef
  public var mic: AssetRef?
  public var systemAudio: AssetRef?
  public var webcam: AssetRef?
  public var events: AssetRef

  public init(
    screen: AssetRef,
    mic: AssetRef? = nil,
    systemAudio: AssetRef? = nil,
    webcam: AssetRef? = nil,
    events: AssetRef
  ) {
    self.screen = screen
    self.mic = mic
    self.systemAudio = systemAudio
    self.webcam = webcam
    self.events = events
  }
}

public struct AssetRef: Codable, Equatable {
  public enum AssetType: String, Codable {
    case screen
    case mic
    case systemAudio
    case webcam
    case events
  }

  public var path: String
  public var type: AssetType
  public var codec: String?
  public var duration: Double?
  public var width: Int?
  public var height: Int?
  public var sampleRate: Int?
  public var channels: Int?
  public var timebase: Double?

  public init(
    path: String,
    type: AssetType,
    codec: String? = nil,
    duration: Double? = nil,
    width: Int? = nil,
    height: Int? = nil,
    sampleRate: Int? = nil,
    channels: Int? = nil,
    timebase: Double? = nil
  ) {
    self.path = path
    self.type = type
    self.codec = codec
    self.duration = duration
    self.width = width
    self.height = height
    self.sampleRate = sampleRate
    self.channels = channels
    self.timebase = timebase
  }
}

public struct Edit: Codable, Equatable {
  public var cuts: [Cut]
  public var speedSegments: [SpeedSegment]
  public var zoomSegments: [ZoomSegment]
  public var cursorOverrides: [CursorOverride]
  public var background: Background
  public var motion: Motion
  public var exportPresets: [ExportPreset]

  public init(
    cuts: [Cut],
    speedSegments: [SpeedSegment],
    zoomSegments: [ZoomSegment],
    cursorOverrides: [CursorOverride],
    background: Background,
    motion: Motion,
    exportPresets: [ExportPreset]
  ) {
    self.cuts = cuts
    self.speedSegments = speedSegments
    self.zoomSegments = zoomSegments
    self.cursorOverrides = cursorOverrides
    self.background = background
    self.motion = motion
    self.exportPresets = exportPresets
  }
}

public struct TimeRange: Codable, Equatable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

public struct Cut: Codable, Equatable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

public struct SpeedSegment: Codable, Equatable {
  public var start: Double
  public var end: Double
  public var rate: Double

  public init(start: Double, end: Double, rate: Double) {
    self.start = start
    self.end = end
    self.rate = rate
  }
}

public struct ZoomSegment: Codable, Equatable {
  public enum Mode: String, Codable {
    case auto
    case manual
  }

  public var start: Double
  public var end: Double
  public var mode: Mode
  public var scale: Double?
  public var targetPoint: TargetPoint?
  public var targetRect: TargetRect?
  public var easing: String?

  public init(
    start: Double,
    end: Double,
    mode: Mode,
    scale: Double? = nil,
    targetPoint: TargetPoint? = nil,
    targetRect: TargetRect? = nil,
    easing: String? = nil
  ) {
    self.start = start
    self.end = end
    self.mode = mode
    self.scale = scale
    self.targetPoint = targetPoint
    self.targetRect = targetRect
    self.easing = easing
  }
}

public struct TargetPoint: Codable, Equatable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct TargetRect: Codable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct CursorOverride: Codable, Equatable {
  public var start: Double
  public var end: Double
  public var hideCursor: Bool?
  public var disableSmoothing: Bool?
  public var cursorScale: Double?

  public init(
    start: Double,
    end: Double,
    hideCursor: Bool? = nil,
    disableSmoothing: Bool? = nil,
    cursorScale: Double? = nil
  ) {
    self.start = start
    self.end = end
    self.hideCursor = hideCursor
    self.disableSmoothing = disableSmoothing
    self.cursorScale = cursorScale
  }
}

public struct Background: Codable, Equatable {
  public enum BackgroundType: String, Codable {
    case color
    case gradient
    case image
  }

  public struct Gradient: Codable, Equatable {
    public var startColor: String?
    public var endColor: String?
    public var angle: Double?

    public init(startColor: String? = nil, endColor: String? = nil, angle: Double? = nil) {
      self.startColor = startColor
      self.endColor = endColor
      self.angle = angle
    }
  }

  public struct Shadow: Codable, Equatable {
    public var radius: Double?
    public var x: Double?
    public var y: Double?
    public var color: String?
    public var opacity: Double?

    public init(
      radius: Double? = nil,
      x: Double? = nil,
      y: Double? = nil,
      color: String? = nil,
      opacity: Double? = nil
    ) {
      self.radius = radius
      self.x = x
      self.y = y
      self.color = color
      self.opacity = opacity
    }
  }

  public var type: BackgroundType
  public var color: String?
  public var gradient: Gradient?
  public var imagePath: String?
  public var padding: Double?
  public var cornerRadius: Double?
  public var shadow: Shadow?

  public init(
    type: BackgroundType,
    color: String? = nil,
    gradient: Gradient? = nil,
    imagePath: String? = nil,
    padding: Double? = nil,
    cornerRadius: Double? = nil,
    shadow: Shadow? = nil
  ) {
    self.type = type
    self.color = color
    self.gradient = gradient
    self.imagePath = imagePath
    self.padding = padding
    self.cornerRadius = cornerRadius
    self.shadow = shadow
  }
}

public struct Motion: Codable, Equatable {
  public enum Style: String, Codable {
    case slow
    case mellow
    case quick
    case rapid
  }

  public struct Spring: Codable, Equatable {
    public var tension: Double?
    public var friction: Double?
    public var mass: Double?

    public init(tension: Double? = nil, friction: Double? = nil, mass: Double? = nil) {
      self.tension = tension
      self.friction = friction
      self.mass = mass
    }
  }

  public var cursorStyle: Style?
  public var zoomStyle: Style?
  public var spring: Spring?

  public init(cursorStyle: Style? = nil, zoomStyle: Style? = nil, spring: Spring? = nil) {
    self.cursorStyle = cursorStyle
    self.zoomStyle = zoomStyle
    self.spring = spring
  }
}

public struct ExportPreset: Codable, Equatable {
  public enum Codec: String, Codable {
    case h264
    case hevc
  }

  public var name: String
  public var width: Int
  public var height: Int
  public var fps: Double
  public var codec: Codec?
  public var bitrate: Int?
  public var quality: Double?

  public init(
    name: String,
    width: Int,
    height: Int,
    fps: Double,
    codec: Codec? = nil,
    bitrate: Int? = nil,
    quality: Double? = nil
  ) {
    self.name = name
    self.width = width
    self.height = height
    self.fps = fps
    self.codec = codec
    self.bitrate = bitrate
    self.quality = quality
  }
}

public enum ProjectModelJSON {
  public static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
