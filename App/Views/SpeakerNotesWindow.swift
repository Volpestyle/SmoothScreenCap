import SwiftUI
import AppKit

// MARK: - Speaker Notes Controller

@MainActor
class SpeakerNotesController: NSObject, ObservableObject {
    static let shared = SpeakerNotesController()

    @Published var isVisible = false
    @Published var notesText: String = ""

    private var notesPanel: NSPanel?

    private override init() {
        super.init()
        // Load saved notes
        notesText = UserDefaults.standard.string(forKey: "speakerNotes") ?? ""
    }

    func showNotes() {
        if notesPanel == nil {
            createPanel()
        }
        notesPanel?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hideNotes() {
        notesPanel?.close()
        isVisible = false
    }

    func toggleNotes() {
        if isVisible {
            hideNotes()
        } else {
            showNotes()
        }
    }

    func saveNotes() {
        UserDefaults.standard.set(notesText, forKey: "speakerNotes")
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Speaker Notes"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Exclude from screen capture
        panel.sharingType = .none

        let contentView = NSHostingView(rootView: SpeakerNotesContentView(controller: self))
        panel.contentView = contentView

        // Restore position
        if let savedFrame = UserDefaults.standard.string(forKey: "speakerNotesFrame") {
            panel.setFrame(from: savedFrame)
        } else {
            panel.center()
        }

        // Save position on move/resize
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            if let panel = panel {
                UserDefaults.standard.set(panel.frameDescriptor, forKey: "speakerNotesFrame")
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            if let panel = panel {
                UserDefaults.standard.set(panel.frameDescriptor, forKey: "speakerNotesFrame")
            }
        }

        panel.delegate = self
        self.notesPanel = panel
    }

    /// Get the window ID for excluding from capture
    var windowID: CGWindowID? {
        guard let panel = notesPanel else { return nil }
        return CGWindowID(panel.windowNumber)
    }
}

extension SpeakerNotesController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.isVisible = false
            self.saveNotes()
        }
    }
}

// MARK: - Speaker Notes Content View

struct SpeakerNotesContentView: View {
    @ObservedObject var controller: SpeakerNotesController

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("SPEAKER NOTES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Hidden from capture")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.1))

            // Notes editor
            TextEditor(text: $controller.notesText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(Color(white: 0.08))
                .onChange(of: controller.notesText) { _, _ in
                    // Debounced save
                    controller.saveNotes()
                }

            // Footer with tips
            HStack {
                Text("Press ⌘⇧N to toggle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(controller.notesText.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.1))
        }
        .frame(minWidth: 300, minHeight: 200)
        .background(Color(white: 0.06))
    }
}

// MARK: - Speaker Notes Toggle Button (for Recording View)

struct SpeakerNotesToggle: View {
    @ObservedObject var controller = SpeakerNotesController.shared

    var body: some View {
        Button {
            controller.toggleNotes()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                    .foregroundStyle(controller.isVisible ? .white : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speaker Notes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    Text(controller.isVisible ? "Window open" : "Click to open")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isVisible {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(controller.isVisible ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(controller.isVisible ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard Shortcut Handler

extension SpeakerNotesController {
    func setupKeyboardShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⇧N to toggle notes
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 45 { // N key
                Task { @MainActor in
                    self?.toggleNotes()
                }
                return nil
            }
            return event
        }
    }
}
