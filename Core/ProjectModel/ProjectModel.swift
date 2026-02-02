import Foundation

public struct ProjectModel: Codable, Equatable {
  public static let currentVersion = "1"
  public static let currentEngineVersion = "0.1.0"
  public static let projectFilename = "project.json"

  public var id: UUID
  public var createdAt: Date
  public var version: String
  public var engineVersion: String
  public var appVersion: String?
  public var assets: Assets
  public var edit: Edit

  public init(
    id: UUID,
    createdAt: Date,
    version: String,
    engineVersion: String = ProjectModel.currentEngineVersion,
    appVersion: String? = nil,
    assets: Assets,
    edit: Edit
  ) {
    self.id = id
    self.createdAt = createdAt
    self.version = version
    self.engineVersion = engineVersion
    self.appVersion = appVersion
    self.assets = assets
    self.edit = edit
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case createdAt
    case version
    case engineVersion
    case appVersion
    case assets
    case edit
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    version = try container.decode(String.self, forKey: .version)
    engineVersion = try container.decodeIfPresent(String.self, forKey: .engineVersion)
      ?? ProjectModel.currentEngineVersion
    appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
    assets = try container.decode(Assets.self, forKey: .assets)
    edit = try container.decode(Edit.self, forKey: .edit)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(version, forKey: .version)
    try container.encode(engineVersion, forKey: .engineVersion)
    try container.encodeIfPresent(appVersion, forKey: .appVersion)
    try container.encode(assets, forKey: .assets)
    try container.encode(edit, forKey: .edit)
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
  public var format: String?
  public var duration: Double?
  public var width: Int?
  public var height: Int?
  public var frameRate: Double?
  public var sampleRate: Int?
  public var channels: Int?
  public var timebase: Double?

  public init(
    path: String,
    type: AssetType,
    codec: String? = nil,
    format: String? = nil,
    duration: Double? = nil,
    width: Int? = nil,
    height: Int? = nil,
    frameRate: Double? = nil,
    sampleRate: Int? = nil,
    channels: Int? = nil,
    timebase: Double? = nil
  ) {
    self.path = path
    self.type = type
    self.codec = codec
    self.format = format
    self.duration = duration
    self.width = width
    self.height = height
    self.frameRate = frameRate
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
  public var cursorSettings: CursorSettings?
  public var audioSettings: AudioSettings?
  public var exportPresets: [ExportPreset]

  public init(
    cuts: [Cut],
    speedSegments: [SpeedSegment],
    zoomSegments: [ZoomSegment],
    cursorOverrides: [CursorOverride],
    background: Background,
    motion: Motion,
    cursorSettings: CursorSettings? = nil,
    audioSettings: AudioSettings? = nil,
    exportPresets: [ExportPreset]
  ) {
    self.cuts = cuts
    self.speedSegments = speedSegments
    self.zoomSegments = zoomSegments
    self.cursorOverrides = cursorOverrides
    self.background = background
    self.motion = motion
    self.cursorSettings = cursorSettings
    self.audioSettings = audioSettings
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

public struct CursorSettings: Codable, Equatable {
  public var scale: Double
  public var clickHighlightEnabled: Bool
  public var clickHighlightColor: String
  public var clickHighlightOpacity: Double
  public var clickSoundEnabled: Bool
  public var clickSoundVolume: Double
  public var idleHideEnabled: Bool
  public var idleHideDelay: Double
  public var smoothingEnabled: Bool
  public var smoothingMinCutoff: Double
  public var smoothingBeta: Double
  public var smoothingDCutoff: Double

  public init(
    scale: Double = 1.5,
    clickHighlightEnabled: Bool = true,
    clickHighlightColor: String = "#FFFFFF",
    clickHighlightOpacity: Double = 0.5,
    clickSoundEnabled: Bool = true,
    clickSoundVolume: Double = 0.6,
    idleHideEnabled: Bool = true,
    idleHideDelay: Double = 2.0,
    smoothingEnabled: Bool = true,
    smoothingMinCutoff: Double = 1.0,
    smoothingBeta: Double = 0.007,
    smoothingDCutoff: Double = 1.0
  ) {
    self.scale = scale
    self.clickHighlightEnabled = clickHighlightEnabled
    self.clickHighlightColor = clickHighlightColor
    self.clickHighlightOpacity = clickHighlightOpacity
    self.clickSoundEnabled = clickSoundEnabled
    self.clickSoundVolume = clickSoundVolume
    self.idleHideEnabled = idleHideEnabled
    self.idleHideDelay = idleHideDelay
    self.smoothingEnabled = smoothingEnabled
    self.smoothingMinCutoff = smoothingMinCutoff
    self.smoothingBeta = smoothingBeta
    self.smoothingDCutoff = smoothingDCutoff
  }

  private enum CodingKeys: String, CodingKey {
    case scale
    case clickHighlightEnabled
    case clickHighlightColor
    case clickHighlightOpacity
    case clickSoundEnabled
    case clickSoundVolume
    case idleHideEnabled
    case idleHideDelay
    case smoothingEnabled
    case smoothingMinCutoff
    case smoothingBeta
    case smoothingDCutoff
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.5
    clickHighlightEnabled = try container.decodeIfPresent(Bool.self, forKey: .clickHighlightEnabled) ?? true
    clickHighlightColor = try container.decodeIfPresent(String.self, forKey: .clickHighlightColor) ?? "#FFFFFF"
    clickHighlightOpacity = try container.decodeIfPresent(Double.self, forKey: .clickHighlightOpacity) ?? 0.5
    clickSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .clickSoundEnabled) ?? true
    clickSoundVolume = try container.decodeIfPresent(Double.self, forKey: .clickSoundVolume) ?? 0.6
    idleHideEnabled = try container.decodeIfPresent(Bool.self, forKey: .idleHideEnabled) ?? true
    idleHideDelay = try container.decodeIfPresent(Double.self, forKey: .idleHideDelay) ?? 2.0
    smoothingEnabled = try container.decodeIfPresent(Bool.self, forKey: .smoothingEnabled) ?? true
    smoothingMinCutoff = try container.decodeIfPresent(Double.self, forKey: .smoothingMinCutoff) ?? 1.0
    smoothingBeta = try container.decodeIfPresent(Double.self, forKey: .smoothingBeta) ?? 0.007
    smoothingDCutoff = try container.decodeIfPresent(Double.self, forKey: .smoothingDCutoff) ?? 1.0
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(scale, forKey: .scale)
    try container.encode(clickHighlightEnabled, forKey: .clickHighlightEnabled)
    try container.encode(clickHighlightColor, forKey: .clickHighlightColor)
    try container.encode(clickHighlightOpacity, forKey: .clickHighlightOpacity)
    try container.encode(clickSoundEnabled, forKey: .clickSoundEnabled)
    try container.encode(clickSoundVolume, forKey: .clickSoundVolume)
    try container.encode(idleHideEnabled, forKey: .idleHideEnabled)
    try container.encode(idleHideDelay, forKey: .idleHideDelay)
    try container.encode(smoothingEnabled, forKey: .smoothingEnabled)
    try container.encode(smoothingMinCutoff, forKey: .smoothingMinCutoff)
    try container.encode(smoothingBeta, forKey: .smoothingBeta)
    try container.encode(smoothingDCutoff, forKey: .smoothingDCutoff)
  }
}

public struct AudioSettings: Codable, Equatable {
  public var microphoneVolume: Double
  public var systemAudioVolume: Double
  public var normalizeAudio: Bool

  public init(
    microphoneVolume: Double = 1.0,
    systemAudioVolume: Double = 0.8,
    normalizeAudio: Bool = true
  ) {
    self.microphoneVolume = microphoneVolume
    self.systemAudioVolume = systemAudioVolume
    self.normalizeAudio = normalizeAudio
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
