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
            cursorTexture = try CursorTextureFactory.makeCursorTexture(device: metalRenderer.device)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func renderFrame(
        at sourceTime: TimeInterval,
        background: Background,
        outputSize: CGSize,
        cursorSettings: CursorSettings? = nil,
        cursorOverrides: [CursorOverride] = []
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

            // Get effective cursor settings
            let settings = cursorSettings ?? CursorSettings()

            // Build cursor layer and click highlight if available
            var cursorLayer: CursorLayer?
            var clickHighlight: ClickHighlight?

            if let interpolator = cursorInterpolator,
               let cursorTexture = cursorTexture {
                let state = interpolator.cursorState(
                    at: sourceTime,
                    cursorSettings: settings,
                    cursorOverrides: cursorOverrides
                )

                // Transform cursor position from source to screen coordinates
                let sourceSize = frameReader.naturalSize
                let screenFrame = screenLayer.frame

                let scaleX = screenFrame.width / sourceSize.width
                let scaleY = screenFrame.height / sourceSize.height

                let screenX = screenFrame.minX + state.position.x * scaleX
                let screenY = screenFrame.minY + state.position.y * scaleY
                let screenPosition = CGPoint(x: screenX, y: screenY)

                if state.isVisible {
                    // Cursor size with user scale setting
                    let baseCursorSize: CGFloat = 24
                    let userScale = CGFloat(settings.scale)
                    let cursorSize = CGSize(width: baseCursorSize * userScale, height: baseCursorSize * userScale)
                    let clickScale: CGFloat = state.isClicking ? 1.3 : 1.0
                    let scaledSize = CGSize(
                        width: cursorSize.width * clickScale,
                        height: cursorSize.height * clickScale
                    )

                    cursorLayer = CursorLayer(
                        texture: cursorTexture,
                        size: scaledSize,
                        position: screenPosition,
                        hotspot: CGPoint(x: scaledSize.width / 2, y: scaledSize.height / 2),
                        opacity: Float(state.opacity)
                    )
                }

                // Build click highlight if enabled and there's an active click
                if settings.clickHighlightEnabled && state.clickProgress > 0 {
                    let highlightColor = RenderColor(hex: settings.clickHighlightColor) ?? RenderColor(red: 1, green: 1, blue: 1, alpha: 1)
                    let colorWithOpacity = RenderColor(
                        red: highlightColor.red,
                        green: highlightColor.green,
                        blue: highlightColor.blue,
                        alpha: Float(settings.clickHighlightOpacity)
                    )

                    // maxRadius scales with cursor size
                    let maxRadius = CGFloat(40 * settings.scale)

                    clickHighlight = ClickHighlight(
                        position: screenPosition,
                        progress: Float(1.0 - state.clickProgress), // Invert: clickProgress goes 1->0, we want 0->1
                        color: colorWithOpacity,
                        maxRadius: maxRadius,
                        enabled: true
                    )
                }
            }

            return RenderFrame(
                outputSize: outputSize,
                background: renderBackground,
                screen: screenLayer,
                cursor: cursorLayer,
                clickHighlight: clickHighlight
            )
        } catch {
            print("Frame render error: \(error)")
            return nil
        }
    }

    func clickTimes(between start: TimeInterval, end: TimeInterval) -> [TimeInterval] {
        cursorInterpolator?.clickTimes(between: start, end: end) ?? []
    }

}
