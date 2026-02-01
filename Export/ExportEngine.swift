import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ProjectModel
import Rendering
import TimeMapping

public struct ExportRequest {
  public var sourceVideoURL: URL
  public var systemAudioURL: URL?
  public var microphoneAudioURL: URL?
  public var timeMapping: TimeMapping
  public var outputURL: URL
  public var preset: ExportPreset
  public var renderer: VideoFrameRenderer
  public var temporaryDirectory: URL
  public var onProgress: ((Double) -> Void)?

  public init(
    sourceVideoURL: URL,
    systemAudioURL: URL? = nil,
    microphoneAudioURL: URL? = nil,
    timeMapping: TimeMapping,
    outputURL: URL,
    preset: ExportPreset,
    renderer: VideoFrameRenderer,
    temporaryDirectory: URL,
    onProgress: ((Double) -> Void)? = nil
  ) {
    self.sourceVideoURL = sourceVideoURL
    self.systemAudioURL = systemAudioURL
    self.microphoneAudioURL = microphoneAudioURL
    self.timeMapping = timeMapping
    self.outputURL = outputURL
    self.preset = preset
    self.renderer = renderer
    self.temporaryDirectory = temporaryDirectory
    self.onProgress = onProgress
  }
}

public final class ExportEngine {
  public enum ExportError: Error {
    case invalidDuration
    case missingVideoTrack
    case missingPixelBufferPool
    case audioExportFailed
    case outputNotReady
  }

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
    guard request.systemAudioURL != nil || request.microphoneAudioURL != nil else {
      return nil
    }
    let composition = try buildAudioComposition(request: request)
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
    exporter.audioTimePitchAlgorithm = .timeDomain
    await exporter.export()
    if exporter.status != .completed {
      throw exporter.error ?? ExportError.audioExportFailed
    }
    return outputURL
  }

  private func buildAudioComposition(request: ExportRequest) throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    let segments = request.timeMapping.segments
    try addAudioTrack(url: request.systemAudioURL, to: composition, segments: segments)
    try addAudioTrack(url: request.microphoneAudioURL, to: composition, segments: segments)
    return composition
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

    var cursor = CMTime.zero
    for segment in segments {
      let start = CMTime(seconds: segment.sourceStart, preferredTimescale: 600)
      let duration = CMTime(seconds: segment.sourceEnd - segment.sourceStart, preferredTimescale: 600)
      let sourceRange = CMTimeRange(start: start, duration: duration)
      try compTrack.insertTimeRange(sourceRange, of: track, at: cursor)
      let targetDuration = CMTime(
        seconds: (segment.sourceEnd - segment.sourceStart) / max(0.01, segment.rate),
        preferredTimescale: 600
      )
      compTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: duration), toDuration: targetDuration)
      cursor = cursor + targetDuration
    }
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
