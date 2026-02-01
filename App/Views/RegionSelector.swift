import SwiftUI
import AppKit

// MARK: - Region Selector Controller

@MainActor
class RegionSelectorController: NSObject {
    private var overlayWindow: NSWindow?
    private var selectionView: RegionSelectionView?
    private var completion: ((CGRect?) -> Void)?

    func showSelector(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        // Create full-screen transparent window
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Create selection view
        let selectionView = RegionSelectionView(frame: screen.frame)
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.finishSelection(with: rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.finishSelection(with: nil)
        }

        window.contentView = selectionView
        self.selectionView = selectionView
        self.overlayWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishSelection(with rect: CGRect?) {
        overlayWindow?.close()
        overlayWindow = nil
        selectionView = nil
        completion?(rect)
        completion = nil
    }
}

// MARK: - Region Selection View

class RegionSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect?
    private var isDrawing = false

    private let instructionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Click and drag to select region • ESC to cancel")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        label.isBordered = false
        label.isEditable = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        return label
    }()

    private let dimensionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        label.isBordered = false
        label.isEditable = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.isHidden = true
        return label
    }()

    private let confirmButton: NSButton = {
        let button = NSButton(title: "CAPTURE THIS REGION", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        button.isHidden = true
        return button
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true

        addSubview(instructionLabel)
        addSubview(dimensionLabel)
        addSubview(confirmButton)

        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)

        // Position instruction label at top center
        instructionLabel.sizeToFit()
        let labelWidth = instructionLabel.frame.width + 32
        instructionLabel.frame = CGRect(
            x: (bounds.width - labelWidth) / 2,
            y: bounds.height - 80,
            width: labelWidth,
            height: 40
        )

        // Setup keyboard monitoring for ESC
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.onCancel?()
                return nil
            }
            return event
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        isDrawing = true
        selectionRect = nil
        confirmButton.isHidden = true
        instructionLabel.stringValue = "Release to confirm selection • ESC to cancel"
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, let start = startPoint else { return }
        currentPoint = convert(event.locationInWindow, from: nil)

        if let current = currentPoint {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            selectionRect = rect

            // Update dimension label
            dimensionLabel.stringValue = "\(Int(rect.width)) × \(Int(rect.height))"
            dimensionLabel.sizeToFit()
            dimensionLabel.frame = CGRect(
                x: rect.midX - dimensionLabel.frame.width / 2 - 8,
                y: rect.maxY + 8,
                width: dimensionLabel.frame.width + 16,
                height: 24
            )
            dimensionLabel.isHidden = false
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDrawing = false

        guard let rect = selectionRect, rect.width > 50 && rect.height > 50 else {
            // Selection too small, reset
            selectionRect = nil
            dimensionLabel.isHidden = true
            instructionLabel.stringValue = "Click and drag to select region • ESC to cancel"
            needsDisplay = true
            return
        }

        // Show confirm button
        instructionLabel.stringValue = "Press ENTER to confirm or drag again to resize"
        confirmButton.frame = CGRect(
            x: rect.midX - 100,
            y: rect.minY - 50,
            width: 200,
            height: 32
        )
        confirmButton.isHidden = false

        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Enter key
            confirmSelection()
        } else if event.keyCode == 53 { // ESC key
            onCancel?()
        }
    }

    @objc private func confirmSelection() {
        guard let rect = selectionRect else { return }

        // Convert to screen coordinates
        guard let screen = NSScreen.main else {
            onCancel?()
            return
        }

        // Flip Y coordinate (NSView uses bottom-left origin, screen uses top-left)
        let screenRect = CGRect(
            x: rect.origin.x,
            y: screen.frame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        onSelectionComplete?(screenRect)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw semi-transparent overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fill(bounds)

        // Draw selection rectangle
        if let rect = selectionRect {
            // Clear the selection area
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            // Draw selection border
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.stroke(rect)

            // Draw corner handles
            let handleSize: CGFloat = 8
            context.setFillColor(NSColor.white.cgColor)

            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]

            for corner in corners {
                let handleRect = CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                context.fillEllipse(in: handleRect)
            }

            // Draw dashed guide lines
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 4])

            // Vertical center line
            context.move(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.strokePath()

            // Horizontal center line
            context.move(to: CGPoint(x: rect.minX, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.strokePath()
        }
    }
}

// MARK: - SwiftUI Bridge

struct RegionSelectorButton: View {
    @EnvironmentObject var appState: AppState
    @State private var isSelecting = false

    var body: some View {
        Button {
            selectRegion()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Region")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    Text(regionDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isRegionSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRegionSelected ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isRegionSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var isRegionSelected: Bool {
        if case .region = appState.selectedSource {
            return true
        }
        return false
    }

    private var regionDescription: String {
        if case .region(let rect) = appState.selectedSource {
            return "\(Int(rect.width)) × \(Int(rect.height))"
        }
        return "Draw area to capture"
    }

    private func selectRegion() {
        let controller = RegionSelectorController()
        controller.showSelector { rect in
            if let rect = rect {
                appState.selectedSource = .region(rect)
            }
        }
    }
}
