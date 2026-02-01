import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    enum AppSection: String, CaseIterable {
        case library = "Library"
        case recording = "Recording"
        case editor = "Editor"
    }

    @Published var currentSection: AppSection = .library
    @Published var currentProject: Project?
    @Published var recentProjects: [Project] = []

    // Recording state
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var selectedSource: CaptureSource?
    @Published var micEnabled = true
    @Published var systemAudioEnabled = true
    @Published var webcamEnabled = false
    @Published var autoZoomEnabled = true
    @Published var hideCursorInCapture = true

    // Editor state
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var selectedSidebarTab: EditorSidebarTab = .background

    init() {
        loadMockProjects()
    }

    private func loadMockProjects() {
        recentProjects = [
            Project(name: "Product Demo v2", duration: 124.5, createdAt: Date().addingTimeInterval(-3600)),
            Project(name: "Bug Repro #423", duration: 45.2, createdAt: Date().addingTimeInterval(-86400)),
            Project(name: "Tutorial - Getting Started", duration: 312.8, createdAt: Date().addingTimeInterval(-172800)),
        ]
    }

    func startRecording() {
        isRecording = true
        recordingDuration = 0
    }

    func stopRecording() {
        isRecording = false
        let newProject = Project(name: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))", duration: recordingDuration, createdAt: Date())
        recentProjects.insert(newProject, at: 0)
        currentProject = newProject
        currentSection = .editor
    }

    func openProject(_ project: Project) {
        currentProject = project
        currentSection = .editor
    }
}

struct Project: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var duration: TimeInterval
    var createdAt: Date
    var thumbnailColor: Color = [.blue, .purple, .orange, .green, .pink].randomElement() ?? .blue
}

enum CaptureSource: Identifiable, Hashable {
    case display(name: String, id: String)
    case window(name: String, id: String)
    case region

    var id: String {
        switch self {
        case .display(_, let id): return "display-\(id)"
        case .window(_, let id): return "window-\(id)"
        case .region: return "region"
        }
    }

    var name: String {
        switch self {
        case .display(let name, _): return name
        case .window(let name, _): return name
        case .region: return "Custom Region"
        }
    }

    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .region: return "viewfinder"
        }
    }
}

enum EditorSidebarTab: String, CaseIterable {
    case background = "Background"
    case cursor = "Cursor"
    case zoom = "Zoom"
    case audio = "Audio"
    case export = "Export"

    var icon: String {
        switch self {
        case .background: return "square.fill"
        case .cursor: return "cursorarrow"
        case .zoom: return "plus.magnifyingglass"
        case .audio: return "waveform"
        case .export: return "square.and.arrow.up"
        }
    }
}
