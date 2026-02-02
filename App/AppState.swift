import SwiftUI
import Combine
import AppKit
import ProjectModel
import ProjectPackaging
import TimeMapping
import AutoZoom
import EventLog
import ExportEngine
import Rendering
import Recording
import ScreenCaptureKit
import AVFoundation
import ClickSound

@MainActor
final class AppState: ObservableObject {

    enum AppSection: String, CaseIterable {
        case library = "Library"
        case recording = "Recording"
        case editor = "Editor"
    }

    // MARK: - Navigation
    @Published var currentSection: AppSection = .library
    @Published var selectedSidebarTab: EditorSidebarTab = .background

    // MARK: - Project Management
    @Published var currentProject: ProjectModel?
    @Published var currentProjectURL: URL?
    @Published var recentProjectURLs: [URL] = []
    @Published var projectMetadata: [URL: ProjectMetadata] = [:]

    // MARK: - Time Mapping (computed from current project)
    @Published private(set) var timeMapper: TimeMapping?

    // MARK: - Preview Rendering
    @Published var previewRenderer: PreviewRenderer?
    @Published var currentPreviewFrame: RenderFrame?
    @Published var isLoadingPreview = false
    @Published var previewOutputSize: CGSize = CGSize(width: 1920, height: 1080)

    // MARK: - Recording State
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var selectedSource: CaptureSource?
    @Published var micEnabled = true
    @Published var systemAudioEnabled = true
    @Published var webcamEnabled = false
    @Published var autoZoomEnabled = true
    @Published var hideCursorInCapture = true
    @AppStorage("eventLoggingEnabled") private var eventLoggingEnabled = true

    // MARK: - Source Management
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var isLoadingSources = false
    @Published var sourceLoadError: String?

    // MARK: - Permissions
    @Published var hasScreenRecordingPermission = false
    @Published var hasMicrophonePermission = false
    @Published var permissionError: PermissionError?

    enum PermissionError: Error, LocalizedError {
        case screenRecordingDenied
        case microphoneDenied
        case screenRecordingNotDetermined

        var errorDescription: String? {
            switch self {
            case .screenRecordingDenied:
                return "Screen recording permission denied. Please enable it in System Settings > Privacy & Security > Screen Recording."
            case .microphoneDenied:
                return "Microphone permission denied. Please enable it in System Settings > Privacy & Security > Microphone."
            case .screenRecordingNotDetermined:
                return "Screen recording permission required. Click to grant access."
            }
        }
    }

    // MARK: - Recording Engine
    private var screenRecorder: ScreenRecorder?
    private var recordingTimer: Timer?
    private var clickSoundPlayer: ClickSoundPlayer?
    private var lastPreviewSourceTime: TimeInterval?

    // MARK: - Source Preview
    let sourcePreviewManager = SourcePreviewManager()

    // MARK: - Device Management
    @Published var availableAudioDevices: [AVCaptureDevice] = []
    @Published var availableVideoDevices: [AVCaptureDevice] = []
    @Published var selectedAudioDeviceID: String?
    @Published var selectedVideoDeviceID: String?

    // MARK: - System Audio App Selection
    @Published var availableAudioApps: [SCRunningApplication] = []
    @Published var selectedAudioAppBundleIDs: Set<String> = []

    // MARK: - Export State
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportError: String?
    @Published var exportSuccess: URL?

    // MARK: - Version Warnings
    @Published var engineVersionWarning: String?

    // MARK: - Playback State
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0 // output time

    var currentSourceTime: TimeInterval? {
        timeMapper?.sourceTime(for: currentTime)
    }

    var outputDuration: TimeInterval {
        timeMapper?.outputDuration ?? currentProject?.assets.screen.duration ?? 0
    }

    var currentProjectName: String {
        currentProjectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    // MARK: - Computed Editor Data
    var zoomSegments: [ZoomSegment] {
        currentProject?.edit.zoomSegments ?? []
    }

    var cuts: [Cut] {
        currentProject?.edit.cuts ?? []
    }

    var speedSegments: [SpeedSegment] {
        currentProject?.edit.speedSegments ?? []
    }

    var cursorOverrides: [CursorOverride] {
        currentProject?.edit.cursorOverrides ?? []
    }

    // MARK: - Initialization

    private let projectManager = ProjectManager()
    private var runtimeEngineVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ProjectModel.currentEngineVersion
    }

    init() {
        loadRecentProjects()
    }

    // MARK: - Project Loading

    private func loadRecentProjects() {
        recentProjectURLs = projectManager.listProjects()
        for url in recentProjectURLs {
            if let metadata = projectManager.loadMetadata(from: url) {
                projectMetadata[url] = metadata
            }
        }
    }

    func openProject(at url: URL) {
        do {
            let project = try projectManager.load(from: url)
            currentProject = project
            currentProjectURL = url
            rebuildTimeMapper()
            warnIfEngineVersionMismatch(project)
            currentSection = .editor
            currentTime = 0
            syncClickSoundPlayer(with: project.edit.cursorSettings ?? CursorSettings())

            // Initialize preview renderer
            Task {
                await loadPreviewRenderer(projectURL: url, project: project)
            }
        } catch {
            print("Failed to load project: \(error)")
        }
    }

    private func loadPreviewRenderer(projectURL: URL, project: ProjectModel) async {
        isLoadingPreview = true

        do {
            let renderer = try PreviewRenderer()
            let screenURL = projectURL.appendingPathComponent(project.assets.screen.path)
            let eventsURL = projectURL.appendingPathComponent(project.assets.events.path)

            await renderer.loadProject(screenVideoURL: screenURL, eventsURL: eventsURL)
            previewRenderer = renderer

            // Render initial frame
            await updatePreviewFrame(outputSize: previewOutputSize)
        } catch {
            print("Failed to initialize preview renderer: \(error)")
        }

        isLoadingPreview = false
    }

    func updatePreviewFrame(outputSize: CGSize? = nil) async {
        guard let renderer = previewRenderer,
              let project = currentProject,
              let sourceTime = currentSourceTime else {
            currentPreviewFrame = nil
            return
        }

        let resolvedSize = outputSize ?? previewOutputSize
        previewOutputSize = resolvedSize
        currentPreviewFrame = await renderer.renderFrame(
            at: sourceTime,
            background: project.edit.background,
            outputSize: resolvedSize,
            cursorSettings: project.edit.cursorSettings,
            cursorOverrides: project.edit.cursorOverrides
        )

        handleClickSounds(
            renderer: renderer,
            sourceTime: sourceTime,
            cursorSettings: project.edit.cursorSettings
        )
    }

    func saveCurrentProject() {
        guard let project = currentProject, let url = currentProjectURL else { return }
        do {
            try projectManager.save(project, to: url)
        } catch {
            print("Failed to save project: \(error)")
        }
    }

    // MARK: - Time Mapping

    func rebuildTimeMapper() {
        guard let project = currentProject,
              let duration = project.assets.screen.duration else {
            timeMapper = nil
            return
        }
        timeMapper = TimeMapping(
            sourceDuration: duration,
            cuts: project.edit.cuts,
            speedSegments: project.edit.speedSegments
        )
    }

    // MARK: - Playback

    func seek(to outputTime: TimeInterval) {
        currentTime = max(0, min(outputTime, outputDuration))

        // Update preview frame (debounced for smooth scrubbing)
        Task {
            await updatePreviewFrame()
        }
    }

    func seekToStart() {
        currentTime = 0
        Task {
            await updatePreviewFrame()
        }
    }

    func seekToEnd() {
        currentTime = outputDuration
        Task {
            await updatePreviewFrame()
        }
    }

    func skipForward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime - seconds)
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            lastPreviewSourceTime = currentSourceTime
        }
    }

    private func syncClickSoundPlayer(with settings: CursorSettings) {
        guard let soundURL = ClickSoundAsset.bundledURL() else { return }
        if let player = clickSoundPlayer {
            player.isEnabled = settings.clickSoundEnabled
            player.volume = Float(settings.clickSoundVolume)
        } else {
            clickSoundPlayer = ClickSoundPlayer(
                soundURL: soundURL,
                volume: Float(settings.clickSoundVolume),
                isEnabled: settings.clickSoundEnabled
            )
        }
    }

    private func makeClickSoundConfiguration(settings: CursorSettings) -> ClickSoundConfiguration? {
        guard settings.clickSoundEnabled, let soundURL = ClickSoundAsset.bundledURL() else { return nil }
        return ClickSoundConfiguration(soundURL: soundURL, volume: settings.clickSoundVolume)
    }

    private func handleClickSounds(
        renderer: PreviewRenderer,
        sourceTime: TimeInterval,
        cursorSettings: CursorSettings?
    ) {
        guard isPlaying else {
            lastPreviewSourceTime = sourceTime
            return
        }

        let settings = cursorSettings ?? CursorSettings()
        guard settings.clickSoundEnabled else {
            lastPreviewSourceTime = sourceTime
            return
        }

        if clickSoundPlayer == nil {
            syncClickSoundPlayer(with: settings)
        } else {
            clickSoundPlayer?.volume = Float(settings.clickSoundVolume)
            clickSoundPlayer?.isEnabled = settings.clickSoundEnabled
        }

        let previousTime = lastPreviewSourceTime ?? sourceTime
        guard sourceTime >= previousTime else {
            lastPreviewSourceTime = sourceTime
            return
        }
        let clicks = renderer.clickTimes(between: previousTime, end: sourceTime)
        for _ in clicks {
            clickSoundPlayer?.play()
        }
        lastPreviewSourceTime = sourceTime
    }

    // MARK: - Source Management

    func refreshSources() async {
        isLoadingSources = true
        sourceLoadError = nil

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            await MainActor.run {
                self.availableDisplays = content.displays
                self.availableWindows = content.windows.filter { window in
                    // Filter out small windows and system windows
                    let width = window.frame.width
                    let height = window.frame.height
                    guard width > 100 && height > 100 else { return false }
                    // Exclude Dock, MenuBar, etc.
                    guard window.owningApplication?.bundleIdentifier != "com.apple.dock" else { return false }
                    return true
                }
                // Get apps that can produce audio
                self.availableAudioApps = content.applications.filter { app in
                    // Filter to apps that are likely to produce audio
                    app.bundleIdentifier != "com.apple.dock" &&
                    app.bundleIdentifier != "com.apple.finder"
                }
                self.hasScreenRecordingPermission = true
                self.isLoadingSources = false
            }
        } catch {
            await MainActor.run {
                self.sourceLoadError = error.localizedDescription
                self.hasScreenRecordingPermission = false
                self.permissionError = .screenRecordingDenied
                self.isLoadingSources = false
            }
        }
    }

    func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            await MainActor.run { hasMicrophonePermission = true }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { hasMicrophonePermission = granted }
        case .denied, .restricted:
            await MainActor.run {
                hasMicrophonePermission = false
                if micEnabled {
                    permissionError = .microphoneDenied
                }
            }
        @unknown default:
            await MainActor.run { hasMicrophonePermission = false }
        }
    }

    func openSystemSettings(for permission: String) {
        let urlString: String
        switch permission {
        case "screenRecording":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case "microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Device Management

    func refreshAudioDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableAudioDevices = discoverySession.devices

        // Select default device if none selected
        if selectedAudioDeviceID == nil, let defaultDevice = AVCaptureDevice.default(for: .audio) {
            selectedAudioDeviceID = defaultDevice.uniqueID
        }
    }

    func refreshVideoDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        availableVideoDevices = discoverySession.devices

        // Select default device if none selected
        if selectedVideoDeviceID == nil, let defaultDevice = AVCaptureDevice.default(for: .video) {
            selectedVideoDeviceID = defaultDevice.uniqueID
        }
    }

    var selectedAudioDevice: AVCaptureDevice? {
        guard let id = selectedAudioDeviceID else {
            return AVCaptureDevice.default(for: .audio)
        }
        return availableAudioDevices.first { $0.uniqueID == id }
    }

    var selectedVideoDevice: AVCaptureDevice? {
        guard let id = selectedVideoDeviceID else {
            return AVCaptureDevice.default(for: .video)
        }
        return availableVideoDevices.first { $0.uniqueID == id }
    }

    // MARK: - Recording

    func startRecording() {
        guard let source = selectedSource else { return }

        Task {
            do {
                let config = try await createRecordingConfiguration(for: source)
                let recorder = ScreenRecorder(configuration: config)
                self.screenRecorder = recorder

                try await recorder.start()

                await MainActor.run {
                    self.isRecording = true
                    self.recordingDuration = 0
                    self.startRecordingTimer()
                }
            } catch {
                await MainActor.run {
                    print("Failed to start recording: \(error)")
                    self.sourceLoadError = "Failed to start recording: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopRecording() {
        guard let recorder = screenRecorder else {
            isRecording = false
            return
        }

        Task {
            do {
                let output = try await recorder.stop()

                await MainActor.run {
                    self.stopRecordingTimer()
                    self.isRecording = false
                    self.screenRecorder = nil

                    // Create project from recording output
                    self.createProjectFromRecordingOutput(output)
                }
            } catch {
                await MainActor.run {
                    print("Failed to stop recording: \(error)")
                    self.isRecording = false
                    self.screenRecorder = nil
                    self.stopRecordingTimer()
                }
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func createRecordingConfiguration(for source: CaptureSource) async throws -> RecordingConfiguration {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter: SCContentFilter
        var width: Int
        var height: Int
        var captureRect: CGRect?
        let includedAudioApps: [SCRunningApplication] = content.applications.filter { app in
            let bundleID = app.bundleIdentifier
            return selectedAudioAppBundleIDs.contains(bundleID)
        }
        let applyAudioFilter = systemAudioEnabled && !selectedAudioAppBundleIDs.isEmpty

        switch source {
        case .display(let display):
            if applyAudioFilter {
                filter = SCContentFilter(display: display, including: includedAudioApps, exceptingWindows: content.windows)
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            width = display.width
            height = display.height
            captureRect = nil
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = Int(window.frame.width)
            height = Int(window.frame.height)
            captureRect = window.frame
        case .region(let rect):
            guard let display = content.displays.first else {
                throw ScreenRecorder.RecordingError.missingVideoDimensions
            }
            if applyAudioFilter {
                filter = SCContentFilter(display: display, including: includedAudioApps, exceptingWindows: content.windows)
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            width = Int(rect.width)
            height = Int(rect.height)
            captureRect = rect
        }

        let projectName = "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        let outputDir = projectManager.newProjectURL(name: projectName)

        let streamConfig = RecordingConfiguration.defaultStreamConfiguration(
            width: width,
            height: height,
            fps: 60,
            captureAudio: systemAudioEnabled
        )
        streamConfig.showsCursor = !hideCursorInCapture

        return RecordingConfiguration(
            filter: filter,
            streamConfiguration: streamConfig,
            outputDirectory: outputDir,
            captureSystemAudio: systemAudioEnabled,
            captureMicrophone: micEnabled,
            captureWebcam: webcamEnabled,
            eventLogging: EventLoggingConfiguration(enabled: eventLoggingEnabled, captureRect: captureRect)
        )
    }

    private func createProjectFromRecordingOutput(_ output: RecordingOutput) {
        let projectURL = output.screenVideoURL.deletingLastPathComponent()
        let projectName = projectURL.deletingPathExtension().lastPathComponent

        Task {
            do {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                let assets = ProjectAssetInputs(
                    screenVideoURL: output.screenVideoURL,
                    systemAudioURL: output.systemAudioURL,
                    microphoneAudioURL: output.microphoneAudioURL,
                    webcamVideoURL: output.webcamVideoURL,
                    eventsURL: output.eventsURL,
                    webcamFormat: output.webcamFormat,
                    webcamFrameRate: output.webcamFrameRate
                )

                let options = ProjectPackagingOptions(
                    appVersion: appVersion,
                    engineVersion: runtimeEngineVersion,
                    defaults: .standard,
                    autoZoomEnabled: autoZoomEnabled,
                    autoZoomConfig: AutoZoom.Config(),
                    outputAspectRatio: nil,
                    filenames: ProjectPackageFilenames()
                )

                let project = try self.projectManager.packageRecording(
                    at: projectURL,
                    assets: assets,
                    options: options
                )

                await MainActor.run {
                    let durationSeconds = project.assets.screen.duration ?? self.recordingDuration
                    self.recentProjectURLs.insert(projectURL, at: 0)
                    self.projectMetadata[projectURL] = ProjectMetadata(
                        name: projectName,
                        duration: durationSeconds,
                        createdAt: project.createdAt,
                        thumbnailColor: .blue
                    )
                    self.currentProject = project
                    self.currentProjectURL = projectURL
                    self.rebuildTimeMapper()
                    self.currentSection = .editor
                }
            } catch {
                await MainActor.run {
                    print("Failed to package project: \(error)")
                    self.sourceLoadError = "Failed to package project: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Edit Operations

    func addCut(start: Double, end: Double) {
        guard var project = currentProject else { return }
        project.edit.cuts.append(Cut(start: start, end: end))
        project.edit.cuts.sort { $0.start < $1.start }
        currentProject = project
        rebuildTimeMapper()
    }

    func removeCut(at index: Int) {
        guard var project = currentProject, index < project.edit.cuts.count else { return }
        project.edit.cuts.remove(at: index)
        currentProject = project
        rebuildTimeMapper()
    }

    func addSpeedSegment(start: Double, end: Double, rate: Double) {
        guard var project = currentProject else { return }
        project.edit.speedSegments.append(SpeedSegment(start: start, end: end, rate: rate))
        project.edit.speedSegments.sort { $0.start < $1.start }
        currentProject = project
        rebuildTimeMapper()
    }

    func updateBackground(_ background: Background) {
        guard var project = currentProject else { return }
        project.edit.background = background
        currentProject = project
    }

    func updateMotion(_ motion: Motion) {
        guard var project = currentProject else { return }
        project.edit.motion = motion
        currentProject = project
    }

    func updateCursorSettings(_ cursorSettings: CursorSettings) {
        guard var project = currentProject else { return }
        project.edit.cursorSettings = cursorSettings
        currentProject = project
        syncClickSoundPlayer(with: cursorSettings)
    }

    func generateAutoZoom(from clicks: [AutoZoom.ClickEvent]) {
        guard var project = currentProject,
              let duration = project.assets.screen.duration,
              let width = project.assets.screen.width,
              let height = project.assets.screen.height else { return }

        let segments = AutoZoom.generateSegments(
            clicks: clicks,
            sourceSize: AutoZoom.Size(width: Double(width), height: Double(height)),
            outputAspectRatio: 16.0 / 9.0,
            duration: duration
        )

        project.edit.zoomSegments = segments
        currentProject = project
    }

    // MARK: - Export

    private func configureCursorOverlay(
        renderer: MetalRenderer,
        project: ProjectModel,
        projectURL: URL
    ) {
        guard let width = project.assets.screen.width,
              let height = project.assets.screen.height else { return }
        let sourceSize = CGSize(width: width, height: height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }

        let eventsURL = projectURL.appendingPathComponent(project.assets.events.path)
        guard let interpolator = try? CursorInterpolator(url: eventsURL) else { return }
        guard let cursorTexture = try? CursorTextureFactory.makeCursorTexture(device: renderer.device) else { return }

        let settings = project.edit.cursorSettings ?? CursorSettings()
        let overrides = project.edit.cursorOverrides
        let cache = CursorStateCache(
            interpolator: interpolator,
            settings: settings,
            overrides: overrides
        )
        let padding = renderer.renderConfiguration.screenPadding

        let screenPosition: (CGPoint, CGSize) -> CGPoint = { point, outputSize in
            let screenFrame = RenderLayout.aspectFitRect(
                sourceSize: sourceSize,
                in: outputSize,
                padding: padding
            )
            let scaleX = screenFrame.width / sourceSize.width
            let scaleY = screenFrame.height / sourceSize.height
            let screenX = screenFrame.minX + point.x * scaleX
            let screenY = screenFrame.minY + point.y * scaleY
            return CGPoint(x: screenX, y: screenY)
        }

        renderer.cursorProvider = { time, context in
            let state = cache.state(at: time.sourceTime)
            guard state.isVisible else { return nil }
            let position = screenPosition(state.position, context.outputSize)
            let baseCursorSize: CGFloat = 24
            let userScale = CGFloat(settings.scale)
            let cursorSize = CGSize(
                width: baseCursorSize * userScale,
                height: baseCursorSize * userScale
            )
            let clickScale: CGFloat = state.isClicking ? 1.3 : 1.0
            let scaledSize = CGSize(
                width: cursorSize.width * clickScale,
                height: cursorSize.height * clickScale
            )
            return CursorLayer(
                texture: cursorTexture,
                size: scaledSize,
                position: position,
                hotspot: CGPoint(x: scaledSize.width / 2, y: scaledSize.height / 2),
                opacity: Float(state.opacity)
            )
        }

        renderer.clickHighlightProvider = { time, context in
            let state = cache.state(at: time.sourceTime)
            guard settings.clickHighlightEnabled, state.clickProgress > 0 else { return nil }
            let position = screenPosition(state.position, context.outputSize)
            let highlightColor = RenderColor(hex: settings.clickHighlightColor)
                ?? RenderColor(red: 1, green: 1, blue: 1, alpha: 1)
            let colorWithOpacity = RenderColor(
                red: highlightColor.red,
                green: highlightColor.green,
                blue: highlightColor.blue,
                alpha: Float(settings.clickHighlightOpacity)
            )
            let maxRadius = CGFloat(40 * settings.scale)
            return ClickHighlight(
                position: position,
                progress: Float(1.0 - state.clickProgress),
                color: colorWithOpacity,
                maxRadius: maxRadius,
                enabled: true
            )
        }
    }

    func startExport(preset: ExportPreset, outputURL: URL) {
        guard let project = currentProject,
              let projectURL = currentProjectURL,
              let mapping = timeMapper else {
            exportError = "No project loaded"
            return
        }

        isExporting = true
        exportProgress = 0
        exportError = nil
        exportSuccess = nil

        let sourceVideoURL = projectURL.appendingPathComponent(project.assets.screen.path)
        let systemAudioURL = project.assets.systemAudio.map { projectURL.appendingPathComponent($0.path) }
        let micAudioURL = project.assets.mic.map { projectURL.appendingPathComponent($0.path) }
        let eventsURL = projectURL.appendingPathComponent(project.assets.events.path)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cursorSettings = project.edit.cursorSettings ?? CursorSettings()
        let clickSoundConfig = makeClickSoundConfiguration(settings: cursorSettings)

        let renderer: VideoFrameRenderer
        do {
            let metalRenderer = try MetalRenderer()
            metalRenderer.renderConfiguration = RenderConfiguration.fromProjectBackground(project.edit.background)
            configureCursorOverlay(renderer: metalRenderer, project: project, projectURL: projectURL)
            renderer = metalRenderer
        } catch {
            isExporting = false
            exportError = "Failed to initialize Metal renderer: \(error.localizedDescription)"
            return
        }

        let request = ExportRequest(
            sourceVideoURL: sourceVideoURL,
            systemAudioURL: systemAudioURL,
            microphoneAudioURL: micAudioURL,
            eventsURL: eventsURL,
            timeMapping: mapping,
            outputURL: outputURL,
            preset: preset,
            renderer: renderer,
            temporaryDirectory: tempDir,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.exportProgress = progress
                }
            },
            engineVersion: runtimeEngineVersion,
            clickSound: clickSoundConfig
        )

        Task {
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let engine = ExportEngine()
                try await engine.export(request)
                await MainActor.run {
                    isExporting = false
                    exportProgress = 1.0
                    exportSuccess = outputURL
                }
                try? FileManager.default.removeItem(at: tempDir)
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }

    func exportToDefaultLocation(preset: ExportPreset) {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let filename = "\(currentProjectName)_\(preset.name).mp4"
        let outputURL = moviesDir.appendingPathComponent(filename)
        startExport(preset: preset, outputURL: outputURL)
    }

    func exportToClipboard(preset: ExportPreset) {
        guard let project = currentProject,
              let projectURL = currentProjectURL,
              let mapping = timeMapper else {
            exportError = "No project loaded"
            return
        }

        isExporting = true
        exportProgress = 0
        exportError = nil
        exportSuccess = nil

        let sourceVideoURL = projectURL.appendingPathComponent(project.assets.screen.path)
        let systemAudioURL = project.assets.systemAudio.map { projectURL.appendingPathComponent($0.path) }
        let micAudioURL = project.assets.mic.map { projectURL.appendingPathComponent($0.path) }
        let eventsURL = projectURL.appendingPathComponent(project.assets.events.path)
        let exportTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cursorSettings = project.edit.cursorSettings ?? CursorSettings()
        let clickSoundConfig = makeClickSoundConfiguration(settings: cursorSettings)

        let renderer: VideoFrameRenderer
        do {
            let metalRenderer = try MetalRenderer()
            metalRenderer.renderConfiguration = RenderConfiguration.fromProjectBackground(project.edit.background)
            configureCursorOverlay(renderer: metalRenderer, project: project, projectURL: projectURL)
            renderer = metalRenderer
        } catch {
            isExporting = false
            exportError = "Failed to initialize Metal renderer: \(error.localizedDescription)"
            return
        }

        let request = ExportRequest(
            sourceVideoURL: sourceVideoURL,
            systemAudioURL: systemAudioURL,
            microphoneAudioURL: micAudioURL,
            eventsURL: eventsURL,
            timeMapping: mapping,
            outputURL: exportTempDir.appendingPathComponent("ssc_clipboard.mp4"),
            preset: preset,
            renderer: renderer,
            temporaryDirectory: exportTempDir,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.exportProgress = progress
                }
            },
            engineVersion: runtimeEngineVersion,
            clickSound: clickSoundConfig
        )

        Task {
            do {
                try FileManager.default.createDirectory(at: exportTempDir, withIntermediateDirectories: true)
                let engine = ExportEngine()
                try await engine.exportToClipboard(request)

                await MainActor.run {
                    isExporting = false
                    exportProgress = 1.0
                    // Use a special marker URL to indicate clipboard success
                    exportSuccess = URL(fileURLWithPath: "/clipboard")
                }

                try? FileManager.default.removeItem(at: exportTempDir)
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
                try? FileManager.default.removeItem(at: exportTempDir)
            }
        }
    }

    // MARK: - Version checks

    private func warnIfEngineVersionMismatch(_ project: ProjectModel) {
        let current = runtimeEngineVersion
        let projectVersion = project.engineVersion
        engineVersionWarning = nil
        let comparison = compareSemanticVersions(projectVersion, current)
        if comparison == .orderedAscending {
            engineVersionWarning = "This project was created with engine \(projectVersion). You're running \(current). Export results may differ."
        } else if comparison == .orderedDescending {
            engineVersionWarning = "This project was created with newer engine \(projectVersion). You're running \(current). Export results may differ."
        }
    }

    private func compareSemanticVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = semanticParts(lhs)
        let rhsParts = semanticParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private func semanticParts(_ version: String) -> [Int] {
        let base = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
        return base.split(separator: ".").map { Int($0) ?? 0 }
    }

    var isClipboardExportSuccess: Bool {
        exportSuccess?.path == "/clipboard"
    }

    func clearExportState() {
        exportError = nil
        exportSuccess = nil
    }
}

// MARK: - Supporting Types

private final class CursorStateCache {
    private let interpolator: CursorInterpolator
    private let settings: CursorSettings
    private let overrides: [CursorOverride]
    private var lastTime: Double?
    private var lastState: CursorInterpolator.CursorState?

    init(interpolator: CursorInterpolator, settings: CursorSettings, overrides: [CursorOverride]) {
        self.interpolator = interpolator
        self.settings = settings
        self.overrides = overrides
    }

    func state(at time: Double) -> CursorInterpolator.CursorState {
        if lastTime == time, let lastState {
            return lastState
        }
        let state = interpolator.cursorState(
            at: time,
            cursorSettings: settings,
            cursorOverrides: overrides
        )
        lastTime = time
        lastState = state
        return state
    }
}

struct ProjectMetadata: Identifiable {
    var id: URL { url ?? URL(fileURLWithPath: "/") }
    var url: URL?
    var name: String
    var duration: TimeInterval
    var createdAt: Date
    var thumbnailColor: Color

    init(name: String, duration: TimeInterval, createdAt: Date, thumbnailColor: Color = .blue) {
        self.name = name
        self.duration = duration
        self.createdAt = createdAt
        self.thumbnailColor = thumbnailColor
    }
}

enum CaptureSource: Identifiable, Hashable {
    case display(SCDisplay)
    case window(SCWindow)
    case region(CGRect)

    var id: String {
        switch self {
        case .display(let display): return "display-\(display.displayID)"
        case .window(let window): return "window-\(window.windowID)"
        case .region(let rect): return "region-\(rect.origin.x)-\(rect.origin.y)-\(rect.width)-\(rect.height)"
        }
    }

    var name: String {
        switch self {
        case .display(let display):
            return "Display \(display.displayID) (\(display.width)×\(display.height))"
        case .window(let window):
            let appName = window.owningApplication?.applicationName ?? "Unknown"
            let windowTitle = window.title ?? "Untitled"
            if windowTitle.isEmpty {
                return appName
            }
            return "\(appName) - \(windowTitle)"
        case .region:
            return "Custom Region"
        }
    }

    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .region: return "viewfinder"
        }
    }

    var appBundleIdentifier: String? {
        switch self {
        case .window(let window):
            return window.owningApplication?.bundleIdentifier
        default:
            return nil
        }
    }

    static func == (lhs: CaptureSource, rhs: CaptureSource) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
