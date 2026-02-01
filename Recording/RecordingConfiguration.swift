import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public struct RecordingFilenames: Equatable {
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

public struct EventLoggingConfiguration: Equatable {
  public var enabled: Bool
  public var captureRect: CGRect?

  public init(enabled: Bool = true, captureRect: CGRect? = nil) {
    self.enabled = enabled
    self.captureRect = captureRect
  }
}

public struct RecordingConfiguration: Equatable {
  public var filter: SCContentFilter
  public var streamConfiguration: SCStreamConfiguration
  public var outputDirectory: URL
  public var filenames: RecordingFilenames
  public var captureSystemAudio: Bool
  public var captureMicrophone: Bool
  public var captureWebcam: Bool
  public var eventLogging: EventLoggingConfiguration

  public init(
    filter: SCContentFilter,
    streamConfiguration: SCStreamConfiguration,
    outputDirectory: URL,
    filenames: RecordingFilenames = RecordingFilenames(),
    captureSystemAudio: Bool = true,
    captureMicrophone: Bool = true,
    captureWebcam: Bool = false,
    eventLogging: EventLoggingConfiguration = EventLoggingConfiguration()
  ) {
    self.filter = filter
    self.streamConfiguration = streamConfiguration
    self.outputDirectory = outputDirectory
    self.filenames = filenames
    self.captureSystemAudio = captureSystemAudio
    self.captureMicrophone = captureMicrophone
    self.captureWebcam = captureWebcam
    self.eventLogging = eventLogging
  }

  public static func defaultStreamConfiguration(
    width: Int,
    height: Int,
    fps: Int = 60,
    captureAudio: Bool = true
  ) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
    config.capturesAudio = captureAudio
    return config
  }
}

public struct RecordingOutput: Equatable {
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
