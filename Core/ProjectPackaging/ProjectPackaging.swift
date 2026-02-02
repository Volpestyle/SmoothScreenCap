import AVFoundation
import AutoZoom
import EventLog
import Foundation
import ProjectModel

public struct ProjectAssetInputs: Equatable {
  public var screenVideoURL: URL
  public var systemAudioURL: URL?
  public var microphoneAudioURL: URL?
  public var webcamVideoURL: URL?
  public var eventsURL: URL?
  public var webcamFormat: String?
  public var webcamFrameRate: Double?

  public init(
    screenVideoURL: URL,
    systemAudioURL: URL? = nil,
    microphoneAudioURL: URL? = nil,
    webcamVideoURL: URL? = nil,
    eventsURL: URL? = nil,
    webcamFormat: String? = nil,
    webcamFrameRate: Double? = nil
  ) {
    self.screenVideoURL = screenVideoURL
    self.systemAudioURL = systemAudioURL
    self.microphoneAudioURL = microphoneAudioURL
    self.webcamVideoURL = webcamVideoURL
    self.eventsURL = eventsURL
    self.webcamFormat = webcamFormat
    self.webcamFrameRate = webcamFrameRate
  }
}

public struct ProjectPackageFilenames: Equatable {
  public var screenVideo: String
  public var systemAudio: String
  public var microphoneAudio: String
  public var webcamVideo: String
  public var events: String

  public init(
    screenVideo: String = "screen.mov",
    systemAudio: String = "system.m4a",
    microphoneAudio: String = "mic.m4a",
    webcamVideo: String = "webcam.mov",
    events: String = "events.jsonl"
  ) {
    self.screenVideo = screenVideo
    self.systemAudio = systemAudio
    self.microphoneAudio = microphoneAudio
    self.webcamVideo = webcamVideo
    self.events = events
  }
}

public struct ProjectDefaults: Equatable {
  public var background: Background
  public var motion: Motion
  public var exportPresets: [ExportPreset]
  public var cuts: [Cut]
  public var speedSegments: [SpeedSegment]
  public var cursorOverrides: [CursorOverride]

  public init(
    background: Background,
    motion: Motion,
    exportPresets: [ExportPreset],
    cuts: [Cut] = [],
    speedSegments: [SpeedSegment] = [],
    cursorOverrides: [CursorOverride] = []
  ) {
    self.background = background
    self.motion = motion
    self.exportPresets = exportPresets
    self.cuts = cuts
    self.speedSegments = speedSegments
    self.cursorOverrides = cursorOverrides
  }

  public static let standard = ProjectDefaults(
    background: Background(
      type: .color,
      color: "#000000",
      padding: 48,
      cornerRadius: 12,
      shadow: Background.Shadow(radius: 18, x: 0, y: 10, color: "#000000", opacity: 0.35)
    ),
    motion: Motion(cursorStyle: .mellow, zoomStyle: .mellow),
    exportPresets: [
      ExportPreset(name: "1080p60", width: 1920, height: 1080, fps: 60, codec: .h264),
      ExportPreset(name: "1080p30", width: 1920, height: 1080, fps: 30, codec: .h264),
      ExportPreset(name: "1440p60", width: 2560, height: 1440, fps: 60, codec: .h264),
      ExportPreset(name: "1440p30", width: 2560, height: 1440, fps: 30, codec: .h264),
      ExportPreset(name: "2160p60", width: 3840, height: 2160, fps: 60, codec: .hevc),
      ExportPreset(name: "2160p30", width: 3840, height: 2160, fps: 30, codec: .hevc)
    ]
  )
}

public struct ProjectPackagingOptions: Equatable {
  public var appVersion: String
  public var engineVersion: String
  public var defaults: ProjectDefaults
  public var autoZoomEnabled: Bool
  public var autoZoomConfig: AutoZoom.Config
  public var outputAspectRatio: Double?
  public var filenames: ProjectPackageFilenames

  public init(
    appVersion: String,
    engineVersion: String = ProjectModel.currentEngineVersion,
    defaults: ProjectDefaults = .standard,
    autoZoomEnabled: Bool = true,
    autoZoomConfig: AutoZoom.Config = AutoZoom.Config(),
    outputAspectRatio: Double? = nil,
    filenames: ProjectPackageFilenames = ProjectPackageFilenames()
  ) {
    self.appVersion = appVersion
    self.engineVersion = engineVersion
    self.defaults = defaults
    self.autoZoomEnabled = autoZoomEnabled
    self.autoZoomConfig = autoZoomConfig
    self.outputAspectRatio = outputAspectRatio
    self.filenames = filenames
  }
}

public enum ProjectPackager {
  public static func writePackage(
    at packageURL: URL,
    assets: ProjectAssetInputs,
    options: ProjectPackagingOptions
  ) throws -> ProjectModel {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

    let screenURL = packageURL.appendingPathComponent(options.filenames.screenVideo)
    try copyIfNeeded(from: assets.screenVideoURL, to: screenURL)

    let systemAudioURL = try copyOptional(
      from: assets.systemAudioURL,
      to: packageURL.appendingPathComponent(options.filenames.systemAudio)
    )
    let micAudioURL = try copyOptional(
      from: assets.microphoneAudioURL,
      to: packageURL.appendingPathComponent(options.filenames.microphoneAudio)
    )
    let webcamURL = try copyOptional(
      from: assets.webcamVideoURL,
      to: packageURL.appendingPathComponent(options.filenames.webcamVideo)
    )
    let eventsURL = try ensureEventsFile(
      source: assets.eventsURL,
      destination: packageURL.appendingPathComponent(options.filenames.events)
    )

    let normalized = ProjectAssetInputs(
      screenVideoURL: screenURL,
      systemAudioURL: systemAudioURL,
      microphoneAudioURL: micAudioURL,
      webcamVideoURL: webcamURL,
      eventsURL: eventsURL,
      webcamFormat: assets.webcamFormat,
      webcamFrameRate: assets.webcamFrameRate
    )
    let project = try buildProject(assets: normalized, options: options)
    let data = try project.encodedJSON(prettyPrinted: true)
    try data.write(to: packageURL.appendingPathComponent(ProjectModel.projectFilename))
    return project
  }

  public static func buildProject(
    assets: ProjectAssetInputs,
    options: ProjectPackagingOptions
  ) throws -> ProjectModel {
    let screenMetadata = try inspectVideo(url: assets.screenVideoURL)
    let screenAsset = AssetRef(
      path: assets.screenVideoURL.lastPathComponent,
      type: .screen,
      codec: screenMetadata.codec,
      duration: screenMetadata.duration,
      width: screenMetadata.width,
      height: screenMetadata.height,
      frameRate: screenMetadata.frameRate,
      timebase: screenMetadata.timebase
    )

    var systemAsset: AssetRef?
    if let url = assets.systemAudioURL {
      let audioMetadata = try inspectAudio(url: url)
      systemAsset = AssetRef(
        path: url.lastPathComponent,
        type: .systemAudio,
        codec: audioMetadata.codec,
        duration: audioMetadata.duration,
        sampleRate: audioMetadata.sampleRate,
        channels: audioMetadata.channels,
        timebase: audioMetadata.timebase
      )
    }

    var micAsset: AssetRef?
    if let url = assets.microphoneAudioURL {
      let audioMetadata = try inspectAudio(url: url)
      micAsset = AssetRef(
        path: url.lastPathComponent,
        type: .mic,
        codec: audioMetadata.codec,
        duration: audioMetadata.duration,
        sampleRate: audioMetadata.sampleRate,
        channels: audioMetadata.channels,
        timebase: audioMetadata.timebase
      )
    }

    var webcamAsset: AssetRef?
    if let url = assets.webcamVideoURL {
      let videoMetadata = try inspectVideo(url: url)
      let frameRate = assets.webcamFrameRate ?? videoMetadata.frameRate
      let timebase = frameRate.map { 1.0 / $0 } ?? videoMetadata.timebase
      webcamAsset = AssetRef(
        path: url.lastPathComponent,
        type: .webcam,
        codec: videoMetadata.codec,
        format: assets.webcamFormat,
        duration: videoMetadata.duration,
        width: videoMetadata.width,
        height: videoMetadata.height,
        frameRate: frameRate,
        timebase: timebase
      )
    }

    let eventsAsset = AssetRef(
      path: options.filenames.events,
      type: .events,
      duration: eventsDuration(from: assets.eventsURL),
      timebase: 1.0
    )

    let assetsModel = Assets(
      screen: screenAsset,
      mic: micAsset,
      systemAudio: systemAsset,
      webcam: webcamAsset,
      events: eventsAsset
    )

    let zoomSegments = try autoZoomSegments(
      enabled: options.autoZoomEnabled,
      eventsURL: assets.eventsURL,
      screenWidth: screenMetadata.width,
      screenHeight: screenMetadata.height,
      outputAspectRatio: options.outputAspectRatio ?? defaultAspectRatio(from: options.defaults.exportPresets),
      duration: screenMetadata.duration,
      config: options.autoZoomConfig
    )

    let edit = Edit(
      cuts: options.defaults.cuts,
      speedSegments: options.defaults.speedSegments,
      zoomSegments: zoomSegments,
      cursorOverrides: options.defaults.cursorOverrides,
      background: options.defaults.background,
      motion: options.defaults.motion,
      cursorSettings: CursorSettings(),
      exportPresets: options.defaults.exportPresets
    )

    let project = ProjectModel(
      id: UUID(),
      createdAt: Date(),
      version: ProjectModel.currentVersion,
      engineVersion: options.engineVersion,
      appVersion: options.appVersion,
      assets: assetsModel,
      edit: edit
    )
    try ProjectValidator.validateOrThrow(project)
    return project
  }

  private static func copyOptional(from source: URL?, to destination: URL) throws -> URL? {
    guard let source else { return nil }
    try copyIfNeeded(from: source, to: destination)
    return destination
  }

  private static func copyIfNeeded(from source: URL, to destination: URL) throws {
    let fileManager = FileManager.default
    if source.standardizedFileURL == destination.standardizedFileURL {
      return
    }
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: source, to: destination)
  }

  private static func ensureEventsFile(source: URL?, destination: URL) throws -> URL {
    let fileManager = FileManager.default
    if let source {
      try copyIfNeeded(from: source, to: destination)
    } else {
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      fileManager.createFile(atPath: destination.path, contents: nil)
    }
    return destination
  }

  private static func autoZoomSegments(
    enabled: Bool,
    eventsURL: URL?,
    screenWidth: Int?,
    screenHeight: Int?,
    outputAspectRatio: Double,
    duration: Double?,
    config: AutoZoom.Config
  ) throws -> [ZoomSegment] {
    guard enabled,
          let eventsURL,
          let screenWidth,
          let screenHeight,
          let duration,
          duration > 0 else {
      return []
    }
    let entries = try EventLogReader.read(from: eventsURL)
    let clicks = entries.compactMap { entry -> AutoZoom.ClickEvent? in
      guard entry.type == .mouse,
            let mouse = entry.mouse,
            mouse.action == .down,
            mouse.button == .left else {
        return nil
      }
      return AutoZoom.ClickEvent(
        time: entry.time,
        location: AutoZoom.Point(x: mouse.location.x, y: mouse.location.y)
      )
    }
    return AutoZoom.generateSegments(
      clicks: clicks,
      sourceSize: AutoZoom.Size(width: Double(screenWidth), height: Double(screenHeight)),
      outputAspectRatio: outputAspectRatio,
      duration: duration,
      config: config
    )
  }

  private static func defaultAspectRatio(from presets: [ExportPreset]) -> Double {
    guard let preset = presets.first, preset.height > 0 else {
      return 16.0 / 9.0
    }
    return Double(preset.width) / Double(preset.height)
  }

  private struct VideoMetadata {
    var duration: Double?
    var width: Int?
    var height: Int?
    var codec: String?
    var frameRate: Double?
    var timebase: Double?
  }

  private struct AudioMetadata {
    var duration: Double?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var timebase: Double?
  }

  private static func inspectVideo(url: URL) throws -> VideoMetadata {
    let asset = AVURLAsset(url: url)
    let duration = asset.duration.seconds.isFinite ? asset.duration.seconds : nil
    guard let track = asset.tracks(withMediaType: .video).first else {
      return VideoMetadata(duration: duration, width: nil, height: nil, codec: nil, frameRate: nil, timebase: nil)
    }

    let natural = track.naturalSize.applying(track.preferredTransform)
    let width = Int(abs(natural.width))
    let height = Int(abs(natural.height))
    let codec = videoCodecString(from: track.formatDescriptions.first)
    let frameRate: Double?
    if track.nominalFrameRate > 0 {
      frameRate = Double(track.nominalFrameRate)
    } else if track.minFrameDuration.isValid && track.minFrameDuration.seconds > 0 {
      frameRate = 1.0 / track.minFrameDuration.seconds
    } else {
      frameRate = nil
    }
    let timebase = frameRate.map { 1.0 / $0 }

    return VideoMetadata(duration: duration, width: width, height: height, codec: codec, frameRate: frameRate, timebase: timebase)
  }

  private static func inspectAudio(url: URL) throws -> AudioMetadata {
    let asset = AVURLAsset(url: url)
    let duration = asset.duration.seconds.isFinite ? asset.duration.seconds : nil
    guard let track = asset.tracks(withMediaType: .audio).first else {
      return AudioMetadata(duration: duration, sampleRate: nil, channels: nil, codec: nil, timebase: nil)
    }

    let codec = audioCodecString(from: track.formatDescriptions.first)
    let sampleRate: Int?
    let channels: Int?
    if let description = track.formatDescriptions.first {
      let formatDescription = description as! CMAudioFormatDescription
      if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
        sampleRate = Int(asbd.pointee.mSampleRate)
        channels = Int(asbd.pointee.mChannelsPerFrame)
      } else {
        sampleRate = nil
        channels = nil
      }
    } else {
      sampleRate = nil
      channels = nil
    }
    let timebase = sampleRate.map { 1.0 / Double($0) }
    return AudioMetadata(duration: duration, sampleRate: sampleRate, channels: channels, codec: codec, timebase: timebase)
  }

  private static func videoCodecString(from description: Any?) -> String? {
    guard let description else { return nil }
    let formatDescription = description as! CMFormatDescription
    let subtype = CMFormatDescriptionGetMediaSubType(formatDescription)
    return normalizeCodec(fourcc: subtype)
  }

  private static func audioCodecString(from description: Any?) -> String? {
    guard let description else { return nil }
    let formatDescription = description as! CMFormatDescription
    let subtype = CMFormatDescriptionGetMediaSubType(formatDescription)
    return normalizeCodec(fourcc: subtype)
  }

  private static func normalizeCodec(fourcc: FourCharCode) -> String {
    let raw = fourCCString(fourcc).lowercased()
    switch raw {
    case "avc1", "h264":
      return "h264"
    case "hvc1", "hev1":
      return "hevc"
    case "mp4a":
      return "aac"
    default:
      return raw
    }
  }

  private static func fourCCString(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF),
      UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF),
      UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "%08x", code)
  }

  private static func eventsDuration(from url: URL?) -> Double? {
    guard let url else { return nil }
    let entries = try? EventLogReader.read(from: url)
    return entries?.map(\.time).max()
  }
}
