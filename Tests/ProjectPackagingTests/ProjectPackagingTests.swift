import AVFoundation
import AutoZoom
import EventLog
import ProjectModel
import ProjectPackaging
import XCTest

final class ProjectPackagingTests: XCTestCase {
  func testPackageWritesProjectAndAssets() throws {
    let temp = try TemporaryDirectory()
    let assetsDir = temp.url.appendingPathComponent("assets")
    try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

    let screenURL = assetsDir.appendingPathComponent("source.mov")
    let micURL = assetsDir.appendingPathComponent("mic.caf")
    let systemURL = assetsDir.appendingPathComponent("system.caf")
    let eventsURL = assetsDir.appendingPathComponent("events.jsonl")

    try makeTestVideo(url: screenURL, frameCount: 3, fps: 3, size: CGSize(width: 120, height: 80))
    try makeToneAudio(url: micURL, duration: 1.0, sampleRate: 48_000)
    try makeToneAudio(url: systemURL, duration: 1.0, sampleRate: 48_000)
    try writeEvents(to: eventsURL, clicks: [
      EventLogEntry(
        time: 0.5,
        mouse: .init(action: .down, button: .left, location: .init(x: 60, y: 40), globalLocation: nil)
      )
    ])

    let packageURL = temp.url.appendingPathComponent("Test.smoothscreencap")
    let assets = ProjectAssetInputs(
      screenVideoURL: screenURL,
      systemAudioURL: systemURL,
      microphoneAudioURL: micURL,
      webcamVideoURL: nil,
      eventsURL: eventsURL
    )

    let options = ProjectPackagingOptions(
      appVersion: "0.1.0",
      defaults: .standard,
      autoZoomEnabled: true,
      autoZoomConfig: AutoZoom.Config(preRoll: 0.1, postRoll: 0.2, settleTime: 0.0),
      outputAspectRatio: 16.0 / 9.0,
      filenames: ProjectPackageFilenames()
    )

    let project = try ProjectPackager.writePackage(at: packageURL, assets: assets, options: options)
    let projectJSON = packageURL.appendingPathComponent(ProjectModel.projectFilename)

    XCTAssertTrue(FileManager.default.fileExists(atPath: projectJSON.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("screen.mov").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("mic.m4a").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("system.m4a").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("events.jsonl").path))

    XCTAssertEqual(project.assets.screen.path, "screen.mov")
    XCTAssertEqual(project.assets.mic?.path, "mic.m4a")
    XCTAssertEqual(project.assets.systemAudio?.path, "system.m4a")
    XCTAssertEqual(project.assets.events.path, "events.jsonl")
    XCTAssertEqual(project.edit.zoomSegments.count, 1)
    XCTAssertEqual(project.edit.exportPresets.count, ProjectDefaults.standard.exportPresets.count)
    XCTAssertNotNil(project.assets.screen.width)
    XCTAssertNotNil(project.assets.screen.height)
    XCTAssertEqual(project.engineVersion, ProjectModel.currentEngineVersion)
  }

  func testWebcamMetadataOverrides() throws {
    let temp = try TemporaryDirectory()
    let screenURL = temp.url.appendingPathComponent("screen.mov")
    let webcamURL = temp.url.appendingPathComponent("webcam.mov")
    try makeTestVideo(url: screenURL, frameCount: 2, fps: 2, size: CGSize(width: 64, height: 64))
    try makeTestVideo(url: webcamURL, frameCount: 2, fps: 2, size: CGSize(width: 320, height: 240))

    let assets = ProjectAssetInputs(
      screenVideoURL: screenURL,
      systemAudioURL: nil,
      microphoneAudioURL: nil,
      webcamVideoURL: webcamURL,
      eventsURL: nil,
      webcamFormat: "yuv420",
      webcamFrameRate: 24.0
    )

    let project = try ProjectPackager.buildProject(
      assets: assets,
      options: ProjectPackagingOptions(appVersion: "0.1.0", defaults: .standard, autoZoomEnabled: false)
    )

    XCTAssertEqual(project.assets.webcam?.format, "yuv420")
    XCTAssertEqual(project.assets.webcam?.frameRate, 24.0)
  }
}

private struct TemporaryDirectory {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("ssc-packaging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    self.url = url
  }
}

private func makeTestVideo(url: URL, frameCount: Int, fps: Int, size: CGSize) throws {
  if FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.removeItem(at: url)
  }
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
  let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(size.width),
    AVVideoHeightKey: Int(size.height)
  ]
  let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
  input.expectsMediaDataInRealTime = false

  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: Int(size.width),
      kCVPixelBufferHeightKey as String: Int(size.height),
      kCVPixelBufferBytesPerRowAlignmentKey as String: Int(size.width) * 4
    ]
  )

  guard writer.canAdd(input) else {
    throw NSError(domain: "ProjectPackagingTests", code: 1)
  }
  writer.add(input)
  writer.startWriting()
  writer.startSession(atSourceTime: .zero)

  for index in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.001)
    }
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      nil,
      &buffer
    )
    if status != kCVReturnSuccess || buffer == nil {
      throw NSError(domain: "ProjectPackagingTests", code: 2)
    }
    let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
    adaptor.append(buffer!, withPresentationTime: time)
  }

  input.markAsFinished()
  let semaphore = DispatchSemaphore(value: 0)
  writer.finishWriting {
    semaphore.signal()
  }
  semaphore.wait()
  if let error = writer.error {
    throw error
  }
}

private func makeToneAudio(url: URL, duration: Double, sampleRate: Double) throws {
  if FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.removeItem(at: url)
  }
  guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
    throw NSError(domain: "ProjectPackagingTests", code: 3)
  }
  let frameCount = AVAudioFrameCount(duration * sampleRate)
  guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
    throw NSError(domain: "ProjectPackagingTests", code: 4)
  }
  buffer.frameLength = frameCount
  let samples = buffer.floatChannelData![0]
  for i in 0..<Int(frameCount) {
    samples[i] = sin(Float(i) * 0.01)
  }
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  try file.write(from: buffer)
}

private func writeEvents(to url: URL, clicks: [EventLogEntry]) throws {
  let data = try EventLogJSONL.encode(clicks)
  try data.write(to: url)
}
