import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ProjectModel
import Rendering
import TimeMapping
import EventLog
#if canImport(AppKit)
import AppKit
#endif

public struct ExportRequest {
  public var sourceVideoURL: URL
  public var systemAudioURL: URL?
  public var microphoneAudioURL: URL?
  public var eventsURL: URL?
  public var timeMapping: TimeMapping
  public var outputURL: URL
  public var preset: ExportPreset
  public var renderer: VideoFrameRenderer
  public var temporaryDirectory: URL
  public var onProgress: ((Double) -> Void)?
  public var engineVersion: String
  public var clickSound: ClickSoundConfiguration?

  public init(
    sourceVideoURL: URL,
    systemAudioURL: URL? = nil,
    microphoneAudioURL: URL? = nil,
    eventsURL: URL? = nil,
    timeMapping: TimeMapping,
    outputURL: URL,
    preset: ExportPreset,
    renderer: VideoFrameRenderer,
    temporaryDirectory: URL,
    onProgress: ((Double) -> Void)? = nil,
    engineVersion: String = ProjectModel.currentEngineVersion,
    clickSound: ClickSoundConfiguration? = nil
  ) {
    self.sourceVideoURL = sourceVideoURL
    self.systemAudioURL = systemAudioURL
    self.microphoneAudioURL = microphoneAudioURL
    self.eventsURL = eventsURL
    self.timeMapping = timeMapping
    self.outputURL = outputURL
    self.preset = preset
    self.renderer = renderer
    self.temporaryDirectory = temporaryDirectory
    self.onProgress = onProgress
    self.engineVersion = engineVersion
    self.clickSound = clickSound
  }
}

public struct ClickSoundConfiguration: Equatable {
  public var soundURL: URL
  public var volume: Double

  public init(soundURL: URL, volume: Double = 0.6) {
    self.soundURL = soundURL
    self.volume = volume
  }
}

public final class ExportEngine {
  public enum ExportError: Error {
    case invalidDuration
    case missingVideoTrack
    case missingPixelBufferPool
    case audioExportFailed
    case outputNotReady
    case clipboardUnavailable
  }

  // Fixed seed for any future randomness to keep exports deterministic.
  public static let deterministicSeed: UInt64 = 0x535343

  public init() {}

  public func export(_ request: ExportRequest) async throws {
    try ensureOutputDirectory(for: request.outputURL)
    if FileManager.default.fileExists(atPath: request.outputURL.path) {
      try FileManager.default.removeItem(at: request.outputURL)
    }
    let audioURL = try await exportAudioIfNeeded(request: request)
    try await exportVideoAndMuxAudio(request: request, audioURL: audioURL)
  }

  private func exportVideoAndMuxAudio(
    request: ExportRequest,
    audioURL: URL?
  ) async throws {
    let asset = AVURLAsset(url: request.sourceVideoURL)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      throw ExportError.missingVideoTrack
    }

    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderTrackOutput(
      track: videoTrack,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferMetalCompatibilityKey as String: true
      ]
    )
    readerOutput.alwaysCopiesSampleData = false
    reader.add(readerOutput)
    reader.startReading()

    let writer = try AVAssetWriter(outputURL: request.outputURL, fileType: .mp4)
    writer.metadata = makeEngineVersionMetadata(engineVersion: request.engineVersion)
    let videoSettings = makeVideoSettings(preset: request.preset)
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoInput) else {
      throw ExportError.outputNotReady
    }
    writer.add(videoInput)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: request.preset.width,
        kCVPixelBufferHeightKey as String: request.preset.height,
        kCVPixelBufferMetalCompatibilityKey as String: true
      ]
    )

    var audioReader: AVAssetReader?
    var audioOutput: AVAssetReaderTrackOutput?
    var audioInput: AVAssetWriterInput?
    if let audioURL {
      let audioAsset = AVURLAsset(url: audioURL)
      if let audioTrack = audioAsset.tracks(withMediaType: .audio).first {
        let audioReaderInstance = try AVAssetReader(asset: audioAsset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        audioReaderInstance.add(output)
        audioReaderInstance.startReading()
        audioReader = audioReaderInstance
        audioOutput = output

        let formatDescription = audioTrack.formatDescriptions.first.map { $0 as! CMFormatDescription }
        let input = AVAssetWriterInput(
          mediaType: .audio,
          outputSettings: nil,
          sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = false
        if writer.canAdd(input) {
          writer.add(input)
          audioInput = input
        }
      }
    }

    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frameProvider = VideoFrameProvider(output: readerOutput)
    let fps = request.preset.fps
    let frameDuration = 1.0 / max(1.0, fps)
    let outputDuration = request.timeMapping.outputDuration
    if outputDuration <= 0 {
      throw ExportError.invalidDuration
    }

    let renderContext = RenderContext(
      outputSize: CGSize(width: request.preset.width, height: request.preset.height),
      pixelFormat: kCVPixelFormatType_32BGRA
    )

    let pool = adaptor.pixelBufferPool ?? makeFallbackPool(
      width: request.preset.width,
      height: request.preset.height,
      pixelFormat: kCVPixelFormatType_32BGRA
    )
    guard let pool else {
      throw ExportError.missingPixelBufferPool
    }

    let totalFrames = Int(ceil(outputDuration * fps))
    var frameIndex = 0
    var lastProgressReport = 0.0
    while true {
      let outputTime = Double(frameIndex) * frameDuration
      if outputTime >= outputDuration - 1e-9 {
        break
      }
      guard let sourceTime = request.timeMapping.sourceTime(for: outputTime) else {
        break
      }
      guard let sourceFrame = frameProvider.frame(at: sourceTime) else {
        break
      }
      var destination: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
      guard let destination else {
        throw ExportError.missingPixelBufferPool
      }

      let renderTime = RenderTime(
        frameIndex: frameIndex,
        outputTime: outputTime,
        sourceTime: sourceTime,
        fps: fps
      )
      try request.renderer.render(
        sourceFrame: sourceFrame,
        destination: destination,
        time: renderTime,
        context: renderContext
      )

      let presentation = CMTime(seconds: outputTime, preferredTimescale: 600)
      waitUntilReady(videoInput)
      adaptor.append(destination, withPresentationTime: presentation)
      frameIndex += 1

      // Report progress every 1% or at least every 30 frames
      let progress = totalFrames > 0 ? Double(frameIndex) / Double(totalFrames) : 0
      if progress - lastProgressReport >= 0.01 || frameIndex % 30 == 0 {
        request.onProgress?(min(progress, 1.0))
        lastProgressReport = progress
      }
    }
    videoInput.markAsFinished()
    request.onProgress?(1.0)

    if let audioOutput, let audioInput {
      while let sample = audioOutput.copyNextSampleBuffer() {
        waitUntilReady(audioInput)
        audioInput.append(sample)
      }
      audioInput.markAsFinished()
    }

    try await finishWriting(writer)

    _ = audioReader
    _ = audioOutput
  }

  private func exportAudioIfNeeded(request: ExportRequest) async throws -> URL? {
    let hasBaseAudio = request.systemAudioURL != nil || request.microphoneAudioURL != nil
    let hasClickSound = request.clickSound != nil && request.eventsURL != nil
    guard hasBaseAudio || hasClickSound else {
      return nil
    }
    let (composition, audioMix) = try buildAudioComposition(request: request)
    if composition.tracks(withMediaType: .audio).isEmpty {
      return nil
    }
    let outputURL = request.temporaryDirectory.appendingPathComponent("ssc_audio.m4a")
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    guard let exporter = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetAppleM4A
    ) else {
      throw ExportError.audioExportFailed
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .m4a
    // Preserve pitch when time-scaling audio for speed segments.
    exporter.audioTimePitchAlgorithm = .timeDomain
    if let audioMix {
      exporter.audioMix = audioMix
    }
    await exporter.export()
    if exporter.status != .completed {
      throw exporter.error ?? ExportError.audioExportFailed
    }
    return outputURL
  }

  private func buildAudioComposition(request: ExportRequest) throws -> (AVMutableComposition, AVAudioMix?) {
    let composition = AVMutableComposition()
    let segments = request.timeMapping.segments
    try addAudioTrack(url: request.systemAudioURL, to: composition, segments: segments)
    try addAudioTrack(url: request.microphoneAudioURL, to: composition, segments: segments)

    var mixParameters: [AVAudioMixInputParameters] = []
    if let clickConfig = request.clickSound, let eventsURL = request.eventsURL {
      let clickTimes = try loadClickTimes(from: eventsURL)
      if !clickTimes.isEmpty {
        let outputTimes = clickTimes.compactMap { request.timeMapping.outputTime(for: $0) }
        let params = try addClickSoundTracks(
          soundURL: clickConfig.soundURL,
          times: outputTimes,
          outputDuration: request.timeMapping.outputDuration,
          to: composition,
          volume: clickConfig.volume
        )
        mixParameters.append(contentsOf: params)
      }
    }

    if mixParameters.isEmpty {
      return (composition, nil)
    }
    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = mixParameters
    return (composition, audioMix)
  }

  private func addAudioTrack(
    url: URL?,
    to composition: AVMutableComposition,
    segments: [TimeMapping.Segment]
  ) throws {
    guard let url else { return }
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else { return }
    guard let compTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else { return }

    for segment in segments {
      let start = CMTime(seconds: segment.sourceStart, preferredTimescale: 600)
      let duration = CMTime(seconds: segment.sourceEnd - segment.sourceStart, preferredTimescale: 600)
      let sourceRange = CMTimeRange(start: start, duration: duration)
      let cursor = CMTime(seconds: segment.outputStart, preferredTimescale: 600)
      try compTrack.insertTimeRange(sourceRange, of: track, at: cursor)
      let targetDuration = CMTime(
        seconds: (segment.sourceEnd - segment.sourceStart) / max(0.01, segment.rate),
        preferredTimescale: 600
      )
      compTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: duration), toDuration: targetDuration)
    }
  }

  private func loadClickTimes(from url: URL) throws -> [Double] {
    let entries = try EventLogReader.read(from: url)
    return entries.compactMap { entry in
      guard let mouse = entry.mouse else { return nil }
      guard mouse.action == .down, mouse.button == .left else { return nil }
      return entry.time
    }
  }

  private func addClickSoundTracks(
    soundURL: URL,
    times: [Double],
    outputDuration: Double,
    to composition: AVMutableComposition,
    volume: Double
  ) throws -> [AVAudioMixInputParameters] {
    guard !times.isEmpty else { return [] }
    let asset = AVURLAsset(url: soundURL)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      return []
    }
    let soundDuration = track.timeRange.duration
    guard soundDuration.isValid, soundDuration.seconds > 0 else {
      return []
    }

    let clampedVolume = Float(max(0, min(1, volume)))
    let sortedTimes = times.sorted()
    var tracks: [AVMutableCompositionTrack] = []
    var trackEndTimes: [CMTime] = []
    var mixParameters: [AVAudioMixInputParameters] = []

    for time in sortedTimes {
      guard time >= 0, time <= outputDuration else { continue }
      let startTime = CMTime(seconds: time, preferredTimescale: 600)
      let endTime = startTime + soundDuration

      var selectedIndex: Int?
      for (index, lastEnd) in trackEndTimes.enumerated() {
        if CMTimeCompare(lastEnd, startTime) <= 0 {
          selectedIndex = index
          break
        }
      }

      let targetTrack: AVMutableCompositionTrack
      if let selectedIndex {
        targetTrack = tracks[selectedIndex]
        trackEndTimes[selectedIndex] = endTime
      } else {
        guard let newTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }
        tracks.append(newTrack)
        trackEndTimes.append(endTime)
        let params = AVMutableAudioMixInputParameters(track: newTrack)
        params.setVolume(clampedVolume, at: .zero)
        mixParameters.append(params)
        targetTrack = newTrack
      }

      try targetTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: soundDuration),
        of: track,
        at: startTime
      )
    }

    return mixParameters
  }

  public func exportToClipboard(_ request: ExportRequest) async throws {
    try FileManager.default.createDirectory(at: request.temporaryDirectory, withIntermediateDirectories: true)
    let tempURL = request.temporaryDirectory.appendingPathComponent("ssc_clipboard_\(UUID().uuidString).mp4")
    var clipboardRequest = request
    clipboardRequest.outputURL = tempURL
    try await export(clipboardRequest)

    #if canImport(AppKit)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let videoData = try Data(contentsOf: tempURL)
    pasteboard.setData(videoData, forType: .init("public.mpeg-4"))
    #else
    throw ExportError.clipboardUnavailable
    #endif

    try? FileManager.default.removeItem(at: tempURL)
  }

  private func makeVideoSettings(preset: ExportPreset) -> [String: Any] {
    var compression: [String: Any] = [:]
    if let bitrate = preset.bitrate {
      compression[AVVideoAverageBitRateKey] = bitrate
    }
    if let quality = preset.quality {
      compression[AVVideoQualityKey] = quality
    }
    let codec: AVVideoCodecType = (preset.codec == .hevc) ? .hevc : .h264
    return [
      AVVideoCodecKey: codec,
      AVVideoWidthKey: preset.width,
      AVVideoHeightKey: preset.height,
      AVVideoCompressionPropertiesKey: compression
    ]
  }

  private func makeEngineVersionMetadata(engineVersion: String) -> [AVMetadataItem] {
    let metadataItem = AVMutableMetadataItem()
    metadataItem.keySpace = .common
    metadataItem.key = AVMetadataKey.commonKeySoftware as (NSCopying & NSObjectProtocol)
    metadataItem.value = "SmoothScreenCap Engine \(engineVersion)" as (NSCopying & NSObjectProtocol)
    return [metadataItem]
  }

  private func waitUntilReady(_ input: AVAssetWriterInput) {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.002)
    }
  }

  private func finishWriting(_ writer: AVAssetWriter) async throws {
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

  private func ensureOutputDirectory(for url: URL) throws {
    let directory = url.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
      if !isDirectory.boolValue {
        throw ExportError.outputNotReady
      }
    } else {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  private func makeFallbackPool(
    width: Int,
    height: Int,
    pixelFormat: OSType
  ) -> CVPixelBufferPool? {
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(
      kCFAllocatorDefault,
      nil,
      attributes as CFDictionary,
      &pool
    )
    return pool
  }
}

private final class VideoFrameProvider {
  private let output: AVAssetReaderTrackOutput
  private var currentSample: CMSampleBuffer?
  private var previousSample: CMSampleBuffer?
  private var isExhausted = false

  init(output: AVAssetReaderTrackOutput) {
    self.output = output
  }

  func frame(at time: Double) -> CVPixelBuffer? {
    let target = CMTime(seconds: time, preferredTimescale: 600)
    if currentSample == nil {
      currentSample = output.copyNextSampleBuffer()
    }

    while let sample = currentSample {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if CMTimeCompare(pts, target) >= 0 {
        break
      }
      previousSample = sample
      currentSample = output.copyNextSampleBuffer()
      if currentSample == nil {
        isExhausted = true
        break
      }
    }

    let chosenSample: CMSampleBuffer?
    if isExhausted {
      chosenSample = previousSample ?? currentSample
    } else if let sample = currentSample {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if CMTimeCompare(pts, target) == 0 || previousSample == nil {
        chosenSample = sample
      } else {
        chosenSample = previousSample
      }
    } else {
      chosenSample = previousSample
    }

    guard let buffer = chosenSample.flatMap({ CMSampleBufferGetImageBuffer($0) }) else {
      return nil
    }
    return buffer
  }
}
