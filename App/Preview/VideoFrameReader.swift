import AVFoundation
import CoreMedia
import CoreVideo

/// Reads video frames from a file at specific timestamps
final class VideoFrameReader {
    private let asset: AVURLAsset
    private let videoTrack: AVAssetTrack
    private var generator: AVAssetImageGenerator

    let duration: TimeInterval
    let naturalSize: CGSize

    init(url: URL) async throws {
        self.asset = AVURLAsset(url: url)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameReaderError.noVideoTrack
        }
        self.videoTrack = track

        let durationCMTime = try await asset.load(.duration)
        self.duration = CMTimeGetSeconds(durationCMTime)

        self.naturalSize = try await track.load(.naturalSize)

        self.generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
    }

    /// Get a CGImage at the specified time
    func frame(at time: TimeInterval) async throws -> CGImage {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: cmTime)
        return image
    }

    /// Get a CVPixelBuffer at the specified time (for Metal rendering)
    func pixelBuffer(at time: TimeInterval) async throws -> CVPixelBuffer {
        let image = try await frame(at: time)
        return try createPixelBuffer(from: image)
    }

    private func createPixelBuffer(from cgImage: CGImage) throws -> CVPixelBuffer {
        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw VideoFrameReaderError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw VideoFrameReaderError.pixelBufferCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    enum VideoFrameReaderError: Error {
        case noVideoTrack
        case pixelBufferCreationFailed
    }
}
