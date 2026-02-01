import AVFoundation
import ExportEngine
import ProjectModel
import Rendering
import TimeMapping
import XCTest

final class AVSyncTests: XCTestCase {
  func testAudioPulseFollowsSpeedChange() async throws {
    let temp = try TemporaryDirectory()
    let sourceVideoURL = temp.url.appendingPathComponent("source.mov")
    let sourceAudioURL = temp.url.appendingPathComponent("system.caf")
    let outputURL = temp.url.appendingPathComponent("output.mp4")

    try await makeTestVideo(
      url: sourceVideoURL,
      frameCount: 4,
      fps: 4,
      size: CGSize(width: 64, height: 64)
    )
    try makePulseAudio(
      url: sourceAudioURL,
      duration: 1.0,
      sampleRate: 48_000,
      pulseTime: 0.5,
      pulseDuration: 0.02
    )

    let mapping = TimeMapping(
      sourceDuration: 1.0,
      cuts: [],
      speedSegments: [SpeedSegment(start: 0, end: 1.0, rate: 2.0)]
    )

    let preset = ExportPreset(
      name: "test",
      width: 64,
      height: 64,
      fps: 4,
      codec: .h264,
      bitrate: 500_000,
      quality: 0.7
    )

    let tempDir = temp.url.appendingPathComponent("tmp")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let request = ExportRequest(
      sourceVideoURL: sourceVideoURL,
      systemAudioURL: sourceAudioURL,
      microphoneAudioURL: nil,
      timeMapping: mapping,
      outputURL: outputURL,
      preset: preset,
      renderer: PassthroughRenderer(),
      temporaryDirectory: tempDir
    )

    let engine = ExportEngine()
    try await engine.export(request)

    let (samples, sampleRate) = try readAudioSamples(from: outputURL)
    guard let pulseIndex = firstPulseIndex(in: samples, threshold: 0.2) else {
      XCTFail("No pulse detected in output audio")
      return
    }

    let pulseTime = Double(pulseIndex) / sampleRate
    let expected = mapping.outputTime(for: 0.5) ?? 0.25
    XCTAssertEqual(pulseTime, expected, accuracy: 0.1)
  }
}

private func makePulseAudio(
  url: URL,
  duration: Double,
  sampleRate: Double,
  pulseTime: Double,
  pulseDuration: Double
) throws {
  if FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.removeItem(at: url)
  }
  guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
    throw NSError(domain: "AVSyncTests", code: 1)
  }
  let frameCount = AVAudioFrameCount(duration * sampleRate)
  guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
    throw NSError(domain: "AVSyncTests", code: 2)
  }
  buffer.frameLength = frameCount

  let samples = buffer.floatChannelData![0]
  let pulseIndex = max(0, min(Int(pulseTime * sampleRate), Int(frameCount - 1)))
  let pulseFrames = max(1, Int(pulseDuration * sampleRate))
  for i in 0..<pulseFrames {
    let index = pulseIndex + i
    if index < Int(frameCount) {
      samples[index] = 0.9
    }
  }

  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  try file.write(from: buffer)
}

private func readAudioSamples(from url: URL) throws -> ([Float], Double) {
  let asset = AVURLAsset(url: url)
  guard let track = asset.tracks(withMediaType: .audio).first else {
    throw NSError(domain: "AVSyncTests", code: 3)
  }

  let reader = try AVAssetReader(asset: asset)
  let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsNonInterleaved: false
  ]
  let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
  output.alwaysCopiesSampleData = false
  reader.add(output)
  reader.startReading()

  var samples: [Float] = []
  var sampleRate: Double = 0

  while let sampleBuffer = output.copyNextSampleBuffer() {
    if sampleRate == 0,
       let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
       let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
      sampleRate = asbd.pointee.mSampleRate
    }

    var blockBuffer: CMBlockBuffer?
    var audioBufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
    )
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    if status != noErr {
      continue
    }

    let bufferList = UnsafeMutableAudioBufferListPointer(&audioBufferList)
    for buffer in bufferList {
      guard let data = buffer.mData else { continue }
      let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
      let pointer = data.assumingMemoryBound(to: Float.self)
      for index in 0..<count {
        samples.append(pointer[index])
      }
    }
  }

  if sampleRate == 0 {
    sampleRate = 48_000
  }

  return (samples, sampleRate)
}

private func firstPulseIndex(in samples: [Float], threshold: Float) -> Int? {
  for (index, sample) in samples.enumerated() {
    if abs(sample) >= threshold {
      return index
    }
  }
  return nil
}

private struct TemporaryDirectory {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
    let name = "ssc-tests-\(UUID().uuidString)"
    let url = base.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    self.url = url
  }
}

private func makeTestVideo(url: URL, frameCount: Int, fps: Int, size: CGSize) async throws {
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
    throw NSError(domain: "AVSyncTests", code: 4)
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
      throw NSError(domain: "AVSyncTests", code: 5)
    }
    let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
    adaptor.append(buffer!, withPresentationTime: time)
  }

  input.markAsFinished()
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
