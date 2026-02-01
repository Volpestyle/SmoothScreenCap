import SwiftUI
import MetalKit
import Rendering
import ProjectModel

/// SwiftUI wrapper for Metal-rendered preview
struct MetalPreviewView: NSViewRepresentable {
    let renderer: PreviewRenderer?
    let frame: RenderFrame?

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = renderer?.metalRenderer.device ?? MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer = renderer
        context.coordinator.currentFrame = frame
        if let device = renderer?.metalRenderer.device, nsView.device !== device {
            nsView.device = device
        }
        if let frame {
            nsView.drawableSize = frame.outputSize
        }
        nsView.setNeedsDisplay(nsView.bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var renderer: PreviewRenderer?
        var currentFrame: RenderFrame?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer = renderer,
                  let frame = currentFrame else { return }

            do {
                try renderer.metalRenderer.render(frame: frame, in: view, waitUntilCompleted: false)
            } catch {
                print("Preview render error: \(error)")
            }
        }
    }
}

/// Manages the preview rendering pipeline
@MainActor
final class PreviewRenderer: ObservableObject {
    let metalRenderer: MetalRenderer

    @Published var currentFrame: RenderFrame?
    @Published var isLoading = false
    @Published var error: Error?

    private var frameReader: VideoFrameReader?
    private var cursorInterpolator: CursorInterpolator?
    private var cursorTexture: MTLTexture?

    init() throws {
        self.metalRenderer = try MetalRenderer()
    }

    func loadProject(screenVideoURL: URL, eventsURL: URL?) async {
        isLoading = true
        error = nil

        do {
            frameReader = try await VideoFrameReader(url: screenVideoURL)

            if let eventsURL = eventsURL {
                cursorInterpolator = try? CursorInterpolator(url: eventsURL)
            }

            // Create cursor texture (simple circle for now)
            cursorTexture = try createCursorTexture()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func renderFrame(
        at sourceTime: TimeInterval,
        background: Background,
        outputSize: CGSize
    ) async -> RenderFrame? {
        guard let frameReader = frameReader else { return nil }

        do {
            let pixelBuffer = try await frameReader.pixelBuffer(at: sourceTime)

            // Build render background
            let renderBackground = RenderBackground(
                background: background,
                image: nil,
                defaultColor: .black
            ) ?? .color(.black)

            // Build screen layer
            let screenLayer = ScreenLayer.fromProjectBackground(
                background,
                screenBuffer: pixelBuffer,
                outputSize: outputSize
            )

            // Build cursor layer if available
            var cursorLayer: CursorLayer?
            if let interpolator = cursorInterpolator,
               let cursorTexture = cursorTexture {
                let state = interpolator.cursorState(at: sourceTime)
                if state.isVisible {
                    // Transform cursor position from source to screen coordinates
                    let sourceSize = frameReader.naturalSize
                    let screenFrame = screenLayer.frame

                    let scaleX = screenFrame.width / sourceSize.width
                    let scaleY = screenFrame.height / sourceSize.height

                    let screenX = screenFrame.minX + state.position.x * scaleX
                    let screenY = screenFrame.minY + state.position.y * scaleY

                    // Cursor size and appearance
                    let cursorSize = CGSize(width: 24, height: 24)
                    let clickScale = state.isClicking ? 1.3 : 1.0
                    let scaledSize = CGSize(
                        width: cursorSize.width * clickScale,
                        height: cursorSize.height * clickScale
                    )

                    cursorLayer = CursorLayer(
                        texture: cursorTexture,
                        size: scaledSize,
                        position: CGPoint(x: screenX, y: screenY),
                        hotspot: CGPoint(x: scaledSize.width / 2, y: scaledSize.height / 2),
                        opacity: state.isVisible ? 1.0 : 0.0
                    )
                }
            }

            return RenderFrame(
                outputSize: outputSize,
                background: renderBackground,
                screen: screenLayer,
                cursor: cursorLayer
            )
        } catch {
            print("Frame render error: \(error)")
            return nil
        }
    }

    private func createCursorTexture() throws -> MTLTexture {
        // Create a simple circle cursor texture
        let size = 64
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = metalRenderer.device.makeTexture(descriptor: textureDescriptor) else {
            throw PreviewRendererError.textureCreationFailed
        }

        // Draw a circle into the texture
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let center = CGFloat(size) / 2
        let radius = CGFloat(size) / 2 - 2

        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - center
                let dy = CGFloat(y) - center
                let distance = sqrt(dx * dx + dy * dy)

                let index = (y * size + x) * 4
                if distance <= radius {
                    // White circle with soft edge
                    let edgeSoftness: CGFloat = 2
                    let alpha = min(1.0, (radius - distance) / edgeSoftness)

                    // BGRA format
                    pixels[index + 0] = 255  // B
                    pixels[index + 1] = 255  // G
                    pixels[index + 2] = 255  // R
                    pixels[index + 3] = UInt8(alpha * 255)  // A
                } else {
                    // Transparent
                    pixels[index + 0] = 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = 0
                    pixels[index + 3] = 0
                }
            }
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )

        return texture
    }

    enum PreviewRendererError: Error {
        case textureCreationFailed
    }
}
