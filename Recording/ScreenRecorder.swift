import AVFoundation
import CoreMedia
import CoreVideo
import EventLog
import Foundation
import ScreenCaptureKit

public final class ScreenRecorder: NSObject {
  public enum RecordingError: Error {
    case invalidOutputDirectory
    case missingVideoDimensions
    case writerInitializationFailed
    case captureNotRunning
  }

  public let configuration: RecordingConfiguration
  private let streamQueue = DispatchQueue(label: "ssc.recording.stream")
  private var stream: SCStream?
  private var videoWriter: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var systemAudioWriter: AVAssetWriter?
  private var systemAudioInput: AVAssetWriterInput?
  private var micAudioWriter: AVAssetWriter?
  private var micAudioInput: AVAssetWriterInput?
  private var micSession: AVCaptureSession?
  private var micOutput: AVCaptureAudioDataOutput?
  private var webcamWriter: AVAssetWriter?
  private var webcamInput: AVAssetWriterInput?
  private var webcamAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var webcamSession: AVCaptureSession?
  private var webcamOutput: AVCaptureVideoDataOutput?
  private var eventWriter: EventLogWriter?
  private var eventMonitor: EventTapMonitor?
  private var recordingStartPTS: CMTime?
  private var recordingStartUptime: TimeInterval?
  private var lastVideoPTS: CMTime?
  private var lastVideoPixelBuffer: CVPixelBuffer?
  private var videoFrameDuration: CMTime = CMTime(value: 1, timescale: 60)
  private var maxSamplePTS: CMTime?
  private var webcamFormat: String?
  private var webcamFrameRate: Double?
  private var isCapturing = false

  public init(configuration: RecordingConfiguration) {
    self.configuration = configuration
  }

  public func start() async throws {
    guard !isCapturing else { return }
    try ensureOutputDirectory()

    let outputURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.screenVideo)
    let systemAudioURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.systemAudio)
    let micAudioURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.microphoneAudio)
    let webcamURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.webcamVideo)

    let streamConfig = configuration.streamConfiguration
    streamConfig.capturesAudio = configuration.captureSystemAudio
    if streamConfig.width == 0 || streamConfig.height == 0 {
      throw RecordingError.missingVideoDimensions
    }
    let clamped = clampVideoDimensions(width: streamConfig.width, height: streamConfig.height)
    if clamped.width != streamConfig.width || clamped.height != streamConfig.height {
      streamConfig.width = clamped.width
      streamConfig.height = clamped.height
    }

    lastVideoPTS = nil
    maxSamplePTS = nil
    lastVideoPixelBuffer = nil
    recordingStartUptime = nil
    let frameInterval = streamConfig.minimumFrameInterval
    if frameInterval.isValid && frameInterval.seconds > 0 {
      videoFrameDuration = frameInterval
    } else {
      videoFrameDuration = CMTime(value: 1, timescale: 60)
    }
    webcamFormat = nil
    webcamFrameRate = nil

    let stream = SCStream(filter: configuration.filter, configuration: streamConfig, delegate: self)
    self.stream = stream
    try await stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
    if configuration.captureSystemAudio {
      try await stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: streamQueue)
    }

    let (videoWriter, videoInput, adaptor) = try makeVideoWriter(
      url: outputURL,
      width: streamConfig.width,
      height: streamConfig.height
    )
    self.videoWriter = videoWriter
    self.videoInput = videoInput
    self.pixelBufferAdaptor = adaptor

    if configuration.captureSystemAudio {
      let audioWriter = try makeAudioWriter(
        url: systemAudioURL,
        sampleRate: 48_000,
        channelCount: 2
      )
      self.systemAudioWriter = audioWriter.writer
      self.systemAudioInput = audioWriter.input
    }

    if configuration.captureMicrophone {
      try setupMicCapture()
      let audioWriter = try makeMicAudioWriter(url: micAudioURL)
      self.micAudioWriter = audioWriter.writer
      self.micAudioInput = audioWriter.input
    }

    if configuration.captureWebcam {
      let webcamSetup = try setupWebcamCapture()
      self.webcamWriter = webcamSetup.writer
      self.webcamInput = webcamSetup.input
      self.webcamAdaptor = webcamSetup.adaptor
    }

    if configuration.eventLogging.enabled {
      let eventsURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.events)
      let writer = try EventLogWriter(url: eventsURL, createIfNeeded: true)
      self.eventWriter = writer
      let startTime = mach_absolute_time()
      let monitor = EventTapMonitor(
        writer: writer,
        captureRect: configuration.eventLogging.captureRect,
        startTime: startTime
      )
      try monitor.start()
      self.eventMonitor = monitor
    }

    recordingStartPTS = nil
    recordingStartUptime = ProcessInfo.processInfo.systemUptime
    try await stream.startCapture()
    if configuration.captureMicrophone {
      micSession?.startRunning()
    }
    if configuration.captureWebcam {
      webcamSession?.startRunning()
    }
    isCapturing = true
  }

  public func stop() async throws -> RecordingOutput {
    guard isCapturing else { throw RecordingError.captureNotRunning }
    isCapturing = false

    if let stream = stream {
      try await stream.stopCapture()
    }

    micSession?.stopRunning()
    micSession = nil
    micOutput = nil
    webcamSession?.stopRunning()
    webcamSession = nil
    webcamOutput = nil

    eventMonitor?.stop()
    eventMonitor = nil
    try eventWriter?.close()
    eventWriter = nil

    let videoURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.screenVideo)
    let systemAudioURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.systemAudio)
    let micAudioURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.microphoneAudio)
    let webcamURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.webcamVideo)
    let eventsURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.events)

    if let start = recordingStartUptime {
      let elapsed = max(0, ProcessInfo.processInfo.systemUptime - start)
      if elapsed > 0 {
        updateMaxSamplePTS(endPTS: CMTime(seconds: elapsed, preferredTimescale: 600))
      }
    }

    streamQueue.sync {
      appendTrailingVideoFramesIfNeeded()
    }

    try await finishWriter(videoWriter, input: videoInput)
    try await finishWriter(systemAudioWriter, input: systemAudioInput)
    try await finishWriter(micAudioWriter, input: micAudioInput)
    try await finishWriter(webcamWriter, input: webcamInput)

    lastVideoPixelBuffer = nil

    return RecordingOutput(
      screenVideoURL: videoURL,
      systemAudioURL: configuration.captureSystemAudio ? systemAudioURL : nil,
      microphoneAudioURL: configuration.captureMicrophone ? micAudioURL : nil,
      webcamVideoURL: configuration.captureWebcam ? webcamURL : nil,
      eventsURL: configuration.eventLogging.enabled ? eventsURL : nil,
      webcamFormat: webcamFormat,
      webcamFrameRate: webcamFrameRate
    )
  }

  private func ensureOutputDirectory() throws {
    let url = configuration.outputDirectory
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      if !isDirectory.boolValue {
        throw RecordingError.invalidOutputDirectory
      }
      return
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func makeVideoWriter(
    url: URL,
    width: Int,
    height: Int
  ) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(configuration.streamConfiguration.pixelFormat),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
      ]
    )

    guard writer.canAdd(input) else {
      throw RecordingError.writerInitializationFailed
    }
    writer.add(input)
    return (writer, input, adaptor)
  }

  private func makeAudioWriter(
    url: URL,
    sampleRate: Int,
    channelCount: Int
  ) throws -> (writer: AVAssetWriter, input: AVAssetWriterInput) {
    let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate == 0 ? 48_000 : sampleRate,
      AVNumberOfChannelsKey: channelCount == 0 ? 2 : channelCount,
      AVEncoderBitRateKey: 192_000
    ]
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw RecordingError.writerInitializationFailed
    }
    writer.add(input)
    return (writer, input)
  }

  private func setupMicCapture() throws {
    let session = AVCaptureSession()
    guard let device = AVCaptureDevice.default(for: .audio) else {
      return
    }
    let input = try AVCaptureDeviceInput(device: device)
    if session.canAddInput(input) {
      session.addInput(input)
    }
    let output = AVCaptureAudioDataOutput()
    output.setSampleBufferDelegate(self, queue: streamQueue)
    if session.canAddOutput(output) {
      session.addOutput(output)
    }
    micSession = session
    micOutput = output
  }

  private func makeMicAudioWriter(url: URL) throws -> (writer: AVAssetWriter, input: AVAssetWriterInput) {
    let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
    let settings = micOutput?.recommendedAudioSettingsForAssetWriter(writingTo: .m4a) as? [String: Any]
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw RecordingError.writerInitializationFailed
    }
    writer.add(input)
    return (writer, input)
  }

  private func setupWebcamCapture() throws -> (writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
    let session = AVCaptureSession()
    guard let device = AVCaptureDevice.default(for: .video) else {
      throw RecordingError.writerInitializationFailed
    }
    let formatDescription = device.activeFormat.formatDescription
    webcamFormat = fourCCString(CMFormatDescriptionGetMediaSubType(formatDescription))
    let minDuration = device.activeVideoMinFrameDuration
    if minDuration.isValid && minDuration.value > 0 {
      webcamFrameRate = Double(minDuration.timescale) / Double(minDuration.value)
    } else {
      webcamFrameRate = nil
    }
    let input = try AVCaptureDeviceInput(device: device)
    if session.canAddInput(input) {
      session.addInput(input)
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    ]
    output.setSampleBufferDelegate(self, queue: streamQueue)
    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    let outputURL = configuration.outputDirectory.appendingPathComponent(configuration.filenames.webcamVideo)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let settings = output.recommendedVideoSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    writerInput.expectsMediaDataInRealTime = true
    guard writer.canAdd(writerInput) else {
      throw RecordingError.writerInitializationFailed
    }
    writer.add(writerInput)

    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: writerInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        kCVPixelBufferWidthKey as String: Int(dimensions.width),
        kCVPixelBufferHeightKey as String: Int(dimensions.height)
      ]
    )

    webcamSession = session
    webcamOutput = output
    return (writer, writerInput, adaptor)
  }

  private func finishWriter(_ writer: AVAssetWriter?, input: AVAssetWriterInput?) async throws {
    guard let writer, writer.status != .completed else { return }
    input?.markAsFinished()
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

  private func clampVideoDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
    let maxDimension = 4096
    guard max(width, height) > maxDimension else {
      return (width, height)
    }
    let scale = Double(maxDimension) / Double(max(width, height))
    let scaledWidth = max(2, Int((Double(width) * scale).rounded()))
    let scaledHeight = max(2, Int((Double(height) * scale).rounded()))
    return (makeEven(scaledWidth), makeEven(scaledHeight))
  }

  private func makeEven(_ value: Int) -> Int {
    value % 2 == 0 ? value : value - 1
  }

  private func storeLastVideoBuffer(_ buffer: CVPixelBuffer, pts: CMTime) {
    // CVPixelBuffer is automatically memory managed in Swift - no need for manual retain/release
    lastVideoPixelBuffer = buffer
    lastVideoPTS = pts
  }

  private func appendRepeatedFrames(
    from startPTS: CMTime,
    to targetPTS: CMTime,
    using pixelBuffer: CVPixelBuffer,
    input: AVAssetWriterInput
  ) {
    guard startPTS.isValid, targetPTS.isValid else { return }
    guard videoFrameDuration.isValid, videoFrameDuration.seconds > 0 else { return }
    let gapSeconds = (targetPTS - startPTS).seconds
    if gapSeconds <= videoFrameDuration.seconds * 1.5 {
      return
    }
    var nextPTS = startPTS + videoFrameDuration
    while CMTimeCompare(nextPTS, targetPTS) < 0 {
      guard input.isReadyForMoreMediaData else { break }
      _ = pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: nextPTS)
      lastVideoPTS = nextPTS
      updateMaxSamplePTS(endPTS: nextPTS)
      nextPTS = nextPTS + videoFrameDuration
    }
  }

  private func appendTrailingVideoFramesIfNeeded() {
    guard let writer = videoWriter,
          let input = videoInput,
          let lastPTS = lastVideoPTS,
          let lastBuffer = lastVideoPixelBuffer,
          let targetPTS = maxSamplePTS else { return }
    guard writer.status == .writing else { return }
    appendRepeatedFrames(from: lastPTS, to: targetPTS, using: lastBuffer, input: input)
  }

  private func updateMaxSamplePTS(with sampleBuffer: CMSampleBuffer) {
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let duration = CMSampleBufferGetDuration(sampleBuffer)
    let endPTS: CMTime
    if duration.isValid && CMTimeCompare(duration, .zero) > 0 {
      endPTS = pts + duration
    } else {
      endPTS = pts
    }
    updateMaxSamplePTS(endPTS: endPTS)
  }

  private func updateMaxSamplePTS(endPTS: CMTime) {
    if let current = maxSamplePTS {
      if CMTimeCompare(endPTS, current) > 0 {
        maxSamplePTS = endPTS
      }
    } else {
      maxSamplePTS = endPTS
    }
  }

  private func fourCCString(_ code: FourCharCode) -> String {
    let bytes: [CChar] = [
      CChar((code >> 24) & 0xff),
      CChar((code >> 16) & 0xff),
      CChar((code >> 8) & 0xff),
      CChar(code & 0xff),
      0
    ]
    return String(cString: bytes)
  }
}

extension ScreenRecorder: SCStreamOutput, SCStreamDelegate {
  public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if recordingStartPTS == nil {
      recordingStartPTS = pts
    }
    guard let offset = recordingStartPTS else { return }
    let retimer = SampleBufferRetimer(offset: offset)
    guard let retimed = retimer.retime(sampleBuffer) else { return }

    switch type {
    case .screen:
      appendVideoSample(retimed)
    case .audio:
      appendSystemAudioSample(retimed)
    default:
      break
    }
  }

  public func stream(_ stream: SCStream, didStopWithError error: Error) {
    // Capture errors are surfaced through stop() by AVAssetWriter error checks.
  }

  private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
    guard let writer = videoWriter, let input = videoInput else { return }
    if writer.status == .unknown {
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if let lastPTS, let lastBuffer = lastVideoPixelBuffer {
      appendRepeatedFrames(from: lastPTS, to: pts, using: lastBuffer, input: input)
    }
    if input.isReadyForMoreMediaData, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      _ = pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: pts)
      storeLastVideoBuffer(pixelBuffer, pts: pts)
      updateMaxSamplePTS(with: sampleBuffer)
    }
  }

  private func appendSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
    guard let writer = systemAudioWriter, let input = systemAudioInput else { return }
    if writer.status == .unknown {
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)
    }
    if input.isReadyForMoreMediaData {
      input.append(sampleBuffer)
      updateMaxSamplePTS(with: sampleBuffer)
    }
  }
}

extension ScreenRecorder: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if recordingStartPTS == nil {
      recordingStartPTS = pts
    }
    guard let offset = recordingStartPTS else { return }
    let retimer = SampleBufferRetimer(offset: offset)
    guard let retimed = retimer.retime(sampleBuffer) else { return }

    if output === micOutput {
      appendMicAudioSample(retimed)
    } else if output === webcamOutput {
      appendWebcamSample(retimed)
    }
  }

  private func appendMicAudioSample(_ sampleBuffer: CMSampleBuffer) {
    guard let writer = micAudioWriter, let input = micAudioInput else { return }
    if writer.status == .unknown {
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)
    }
    if input.isReadyForMoreMediaData {
      input.append(sampleBuffer)
      updateMaxSamplePTS(with: sampleBuffer)
    }
  }

  private func appendWebcamSample(_ sampleBuffer: CMSampleBuffer) {
    guard let writer = webcamWriter, let input = webcamInput else { return }
    if writer.status == .unknown {
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)
    }
    if input.isReadyForMoreMediaData {
      if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        _ = webcamAdaptor?.append(pixelBuffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        updateMaxSamplePTS(with: sampleBuffer)
      }
    }
  }

  // MARK: - Stub functions for Agent B to implement

  /// Returns the last recorded presentation timestamp
  private var lastPTS: CMTime? {
    lastVideoPTS
  }
}
