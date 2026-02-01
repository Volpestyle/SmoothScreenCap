import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit

/// Manages live preview of capture sources before recording
@MainActor
final class SourcePreviewManager: NSObject, ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var isActive = false
    @Published var error: String?

    private var stream: SCStream?
    private var currentSource: CaptureSource?
    private let streamQueue = DispatchQueue(label: "ssc.preview.stream")
    private let ciContext = CIContext()

    func startPreview(for source: CaptureSource) async {
        // Stop existing preview
        await stopPreview()

        currentSource = source
        error = nil

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            let filter: SCContentFilter
            var width: Int
            var height: Int

            switch source {
            case .display(let display):
                filter = SCContentFilter(display: display, excludingWindows: [])
                width = display.width
                height = display.height

            case .window(let window):
                filter = SCContentFilter(desktopIndependentWindow: window)
                width = Int(window.frame.width)
                height = Int(window.frame.height)

            case .region(let rect):
                guard let display = content.displays.first else {
                    error = "No display available"
                    return
                }
                filter = SCContentFilter(display: display, excludingWindows: [])
                width = Int(rect.width)
                height = Int(rect.height)
            }

            // Scale down for preview (max 960px width for performance)
            let scale = min(1.0, 960.0 / Double(width))
            let previewWidth = Int(Double(width) * scale)
            let previewHeight = Int(Double(height) * scale)

            let config = SCStreamConfiguration()
            config.width = previewWidth
            config.height = previewHeight
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30fps preview
            config.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            self.stream = stream

            try await stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
            try await stream.startCapture()

            isActive = true

        } catch {
            self.error = error.localizedDescription
            isActive = false
        }
    }

    func stopPreview() async {
        guard let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            // Ignore stop errors
        }

        self.stream = nil
        self.isActive = false
        self.currentFrame = nil
        self.currentSource = nil
    }

    func updateSource(_ source: CaptureSource?) async {
        guard let source = source else {
            await stopPreview()
            return
        }

        // Only restart if source changed
        if currentSource != source {
            await startPreview(for: source)
        }
    }
}

extension SourcePreviewManager: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Convert to CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        Task { @MainActor in
            self.currentFrame = cgImage
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.error = error.localizedDescription
            self.isActive = false
        }
    }
}
