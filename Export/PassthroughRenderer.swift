import Accelerate
import CoreVideo
import Rendering

public struct PassthroughRenderer: VideoFrameRenderer {
    public init() {}

    public func render(
        sourceFrame: CVPixelBuffer,
        destination: CVPixelBuffer,
        time: RenderTime,
        context: RenderContext
    ) throws {
        CVPixelBufferLockBaseAddress(sourceFrame, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(sourceFrame, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }

        let srcWidth = CVPixelBufferGetWidth(sourceFrame)
        let srcHeight = CVPixelBufferGetHeight(sourceFrame)
        let dstWidth = CVPixelBufferGetWidth(destination)
        let dstHeight = CVPixelBufferGetHeight(destination)

        guard let srcBase = CVPixelBufferGetBaseAddress(sourceFrame),
              let dstBase = CVPixelBufferGetBaseAddress(destination) else {
            return
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(sourceFrame)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(destination)

        // If dimensions match, do a direct copy
        if srcWidth == dstWidth && srcHeight == dstHeight {
            for row in 0..<srcHeight {
                let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
                let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
                memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
            }
            return
        }

        // Scale using Accelerate
        var srcBuffer = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(srcHeight),
            width: vImagePixelCount(srcWidth),
            rowBytes: srcBytesPerRow
        )

        var dstBuffer = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(dstHeight),
            width: vImagePixelCount(dstWidth),
            rowBytes: dstBytesPerRow
        )

        vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
    }
}
