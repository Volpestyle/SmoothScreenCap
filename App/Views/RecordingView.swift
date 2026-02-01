import SwiftUI
import ScreenCaptureKit
import AVFoundation

struct RecordingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Left panel - Source selection
            SourcePickerPanel()

            // Center - Preview area
            RecordingPreviewPanel()

            // Right panel - Settings
            RecordingSettingsPanel()
        }
        .background(Color(white: 0.04))
        .task {
            await appState.refreshSources()
            await appState.checkMicrophonePermission()
        }
    }
}

// MARK: - Source Picker Panel

struct SourcePickerPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "CAPTURE SOURCE")

            if !appState.hasScreenRecordingPermission {
                PermissionRequiredView(
                    title: "Screen Recording Required",
                    message: "Grant screen recording permission to capture your display.",
                    buttonTitle: "Open System Settings"
                ) {
                    appState.openSystemSettings(for: "screenRecording")
                }
            } else if appState.isLoadingSources {
                LoadingSourcesView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Displays section
                        if !appState.availableDisplays.isEmpty {
                            SourceSection(title: "DISPLAYS") {
                                ForEach(appState.availableDisplays, id: \.displayID) { display in
                                    let source = CaptureSource.display(display)
                                    SourceOptionRow(
                                        source: source,
                                        isSelected: appState.selectedSource == source
                                    ) {
                                        appState.selectedSource = source
                                    }
                                }
                            }
                        }

                        // Windows section
                        if !appState.availableWindows.isEmpty {
                            SourceSection(title: "WINDOWS") {
                                ForEach(appState.availableWindows, id: \.windowID) { window in
                                    let source = CaptureSource.window(window)
                                    SourceOptionRow(
                                        source: source,
                                        isSelected: appState.selectedSource == source,
                                        appIcon: getAppIcon(for: window)
                                    ) {
                                        appState.selectedSource = source
                                    }
                                }
                            }
                        }

                        // Region option
                        SourceSection(title: "CUSTOM") {
                            RegionSelectorButton()
                        }
                    }
                    .padding(16)
                }

                // Refresh button
                HStack {
                    Button {
                        Task {
                            await appState.refreshSources()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("REFRESH")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(16)
                .background(Color.white.opacity(0.02))
            }
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
    }

    private func getAppIcon(for window: SCWindow) -> NSImage? {
        guard let bundleID = window.owningApplication?.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - Preview Panel

struct RecordingPreviewPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var previewManager: SourcePreviewManager
    @State private var pulsingOpacity: Double = 1.0

    init() {
        // Will be injected via environmentObject, but need placeholder
        _previewManager = ObservedObject(wrappedValue: SourcePreviewManager())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )

                if appState.isRecording {
                    // Recording indicator overlay
                    RecordingOverlay(
                        duration: appState.recordingDuration,
                        sourceName: appState.selectedSource?.name ?? "Recording"
                    )
                } else if let frame = appState.sourcePreviewManager.currentFrame {
                    // Live preview
                    LivePreviewView(frame: frame)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            // Source name badge
                            VStack {
                                HStack {
                                    SourceBadge(source: appState.selectedSource)
                                    Spacer()
                                    if appState.sourcePreviewManager.isActive {
                                        LiveIndicator()
                                    }
                                }
                                Spacer()
                            }
                            .padding(12)
                        )
                } else if let source = appState.selectedSource {
                    // Loading or no preview available
                    VStack(spacing: 16) {
                        if appState.sourcePreviewManager.isActive {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading preview...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: source.icon)
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text(source.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let error = appState.sourcePreviewManager.error {
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            } else {
                                Text("Preview will appear here")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(24)
                } else {
                    // No source selected
                    VStack(spacing: 16) {
                        Image(systemName: "display")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Select a capture source")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Record button area
            RecordButtonBar()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: appState.selectedSource) { _, newSource in
            Task {
                if appState.isRecording {
                    await appState.sourcePreviewManager.stopPreview()
                } else {
                    await appState.sourcePreviewManager.updateSource(newSource)
                }
            }
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            Task {
                if isRecording {
                    await appState.sourcePreviewManager.stopPreview()
                } else if let source = appState.selectedSource {
                    await appState.sourcePreviewManager.startPreview(for: source)
                }
            }
        }
        .task {
            // Start preview when view appears
            if let source = appState.selectedSource, !appState.isRecording {
                await appState.sourcePreviewManager.startPreview(for: source)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - floor(duration)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Live Preview View

struct LivePreviewView: View {
    let frame: CGImage

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: frame, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Recording Overlay

struct RecordingOverlay: View {
    let duration: TimeInterval
    let sourceName: String
    @State private var pulsingOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 20) {
            // Recording indicator
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
                    .opacity(pulsingOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulsingOpacity = 0.3
                        }
                    }

                Text("RECORDING")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
            }

            // Duration
            Text(formatDuration(duration))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            // Source name
            Text(sourceName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - floor(duration)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: CaptureSource?

    var body: some View {
        if let source = source {
            HStack(spacing: 6) {
                Image(systemName: source.icon)
                    .font(.system(size: 10))
                Text(badgeText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
        }
    }

    private var badgeText: String {
        switch source {
        case .display: return "DISPLAY"
        case .window: return "WINDOW"
        case .region: return "REGION"
        case .none: return ""
        }
    }
}

// MARK: - Live Indicator

struct LiveIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .opacity(isAnimating ? 1.0 : 0.5)

            Text("LIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Record Button Bar

struct RecordButtonBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 24) {
            if appState.isRecording {
                Button {
                    appState.stopRecording()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                        Text("STOP RECORDING")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    appState.startRecording()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("START RECORDING")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canRecord ? Color(white: 0.15) : Color(white: 0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(canRecord ? Color.white.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canRecord)
                .opacity(canRecord ? 1.0 : 0.5)
            }
        }
        .padding(24)
        .background(Color(white: 0.06))
    }

    private var canRecord: Bool {
        appState.selectedSource != nil && appState.hasScreenRecordingPermission
    }
}

// MARK: - Recording Settings Panel

struct RecordingSettingsPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var showAudioAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "AUDIO")

            VStack(spacing: 12) {
                // Microphone with device selection
                DeviceToggleRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    isOn: $appState.micEnabled,
                    hasWarning: appState.micEnabled && !appState.hasMicrophonePermission,
                    warningAction: {
                        appState.openSystemSettings(for: "microphone")
                    },
                    devices: appState.availableAudioDevices,
                    selectedDeviceID: $appState.selectedAudioDeviceID,
                    permissionGranted: appState.hasMicrophonePermission
                )

                // System Audio with app picker
                SystemAudioToggleRow(
                    isOn: $appState.systemAudioEnabled,
                    selectedApps: appState.selectedAudioAppBundleIDs,
                    availableApps: appState.availableAudioApps,
                    onShowPicker: { showAudioAppPicker = true }
                )
            }
            .padding(16)

            Divider()
                .background(Color.white.opacity(0.06))

            SidebarSectionHeader(title: "VIDEO")

            VStack(spacing: 12) {
                // Webcam with device selection
                DeviceToggleRow(
                    icon: "video.fill",
                    title: "Webcam",
                    isOn: $appState.webcamEnabled,
                    devices: appState.availableVideoDevices,
                    selectedDeviceID: $appState.selectedVideoDeviceID,
                    permissionGranted: true
                )

                ToggleRow(
                    icon: "cursorarrow",
                    title: "Hide System Cursor",
                    subtitle: "Render custom cursor",
                    isOn: $appState.hideCursorInCapture
                )
            }
            .padding(16)

            Divider()
                .background(Color.white.opacity(0.06))

            SidebarSectionHeader(title: "AUTOMATION")

            VStack(spacing: 12) {
                ToggleRow(
                    icon: "plus.magnifyingglass",
                    title: "Auto-Zoom",
                    subtitle: "Zoom to click locations",
                    isOn: $appState.autoZoomEnabled
                )
            }
            .padding(16)

            Divider()
                .background(Color.white.opacity(0.06))

            SidebarSectionHeader(title: "TOOLS")

            VStack(spacing: 12) {
                SpeakerNotesToggle()
            }
            .padding(16)

            Spacer()

            // Hotkey config entry point
            HotkeyConfigSection()
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .sheet(isPresented: $showAudioAppPicker) {
            AudioAppPickerSheet(
                availableApps: appState.availableAudioApps,
                selectedBundleIDs: $appState.selectedAudioAppBundleIDs
            )
        }
        .onAppear {
            appState.refreshAudioDevices()
            appState.refreshVideoDevices()
        }
    }
}

// MARK: - Device Toggle Row

struct DeviceToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var hasWarning: Bool = false
    var warningAction: (() -> Void)?
    let devices: [AVCaptureDevice]
    @Binding var selectedDeviceID: String?
    var permissionGranted: Bool = true

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main toggle row
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? (hasWarning ? .orange : .white) : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)

                        if hasWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(selectedDeviceName)
                        .font(.system(size: 10))
                        .foregroundStyle(hasWarning ? .orange : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if hasWarning, let action = warningAction {
                    Button(action: action) {
                        Text("FIX")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                if isOn && devices.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .padding(12)

            // Device picker (expandable)
            if isOn && isExpanded && devices.count > 1 {
                VStack(spacing: 4) {
                    ForEach(devices, id: \.uniqueID) { device in
                        DeviceOptionRow(
                            device: device,
                            isSelected: selectedDeviceID == device.uniqueID
                        ) {
                            selectedDeviceID = device.uniqueID
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(hasWarning ? Color.orange.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var selectedDeviceName: String {
        if !permissionGranted {
            return "Permission required"
        }
        if let id = selectedDeviceID,
           let device = devices.first(where: { $0.uniqueID == id }) {
            return device.localizedName
        }
        return devices.first?.localizedName ?? "No device"
    }
}

struct DeviceOptionRow: View {
    let device: AVCaptureDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .green : .secondary)

                Text(device.localizedName)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System Audio Toggle Row

struct SystemAudioToggleRow: View {
    @Binding var isOn: Bool
    let selectedApps: Set<String>
    let availableApps: [SCRunningApplication]
    let onShowPicker: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(isOn ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("System Audio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isOn {
                Button(action: onShowPicker) {
                    Text("SELECT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var subtitleText: String {
        if selectedApps.isEmpty {
            return "All apps"
        } else if selectedApps.count == 1 {
            if let bundleID = selectedApps.first,
               let app = availableApps.first(where: { $0.bundleIdentifier == bundleID }) {
                return app.applicationName
            }
            return "1 app selected"
        } else {
            return "\(selectedApps.count) apps selected"
        }
    }
}

// MARK: - Audio App Picker Sheet

struct AudioAppPickerSheet: View {
    let availableApps: [SCRunningApplication]
    @Binding var selectedBundleIDs: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SELECT APPS TO CAPTURE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(16)
            .background(Color(white: 0.08))

            // All apps toggle
            HStack {
                Image(systemName: selectedBundleIDs.isEmpty ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selectedBundleIDs.isEmpty ? .green : .secondary)

                Text("All Applications")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(12)
            .background(selectedBundleIDs.isEmpty ? Color.white.opacity(0.05) : Color.clear)
            .onTapGesture {
                selectedBundleIDs.removeAll()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // App list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(availableApps.sorted { $0.applicationName < $1.applicationName }, id: \.bundleIdentifier) { app in
                        AppSelectionRow(
                            app: app,
                            isSelected: selectedBundleIDs.contains(app.bundleIdentifier)
                        ) {
                            if selectedBundleIDs.contains(app.bundleIdentifier) {
                                selectedBundleIDs.remove(app.bundleIdentifier)
                            } else {
                                selectedBundleIDs.insert(app.bundleIdentifier)
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 320, height: 400)
        .background(Color(white: 0.06))
    }
}

struct AppSelectionRow: View {
    let app: SCRunningApplication
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // App icon
                if let icon = getAppIcon() {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                Text(app.applicationName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func getAppIcon() -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - Hotkey Config Section

struct HotkeyConfigSection: View {
    var body: some View {
        Button {
            // Open settings to hotkeys
            if let url = URL(string: "smoothscreencap://settings/hotkeys") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HOTKEYS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "gear")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("⌘ R")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)

                    Text("Start / Stop")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.02))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Views

struct SourceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                content
            }
        }
    }
}

struct SourceOptionRow: View {
    let source: CaptureSource
    let isSelected: Bool
    var appIcon: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: source.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text(sourceTypeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var sourceTypeLabel: String {
        switch source {
        case .display: return "Display"
        case .window: return "Window"
        case .region: return "Custom Area"
        }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var hasWarning: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? (hasWarning ? .orange : .white) : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    if hasWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(hasWarning ? .orange : .secondary)
            }

            Spacer()

            if let onTap = onTap, hasWarning {
                Button {
                    onTap()
                } label: {
                    Text("FIX")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(hasWarning ? Color.orange.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct PermissionRequiredView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingSourcesView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading sources...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// SidebarSectionHeader is defined in LibraryView.swift and shared across views

#Preview {
    RecordingView()
        .environmentObject(AppState())
        .frame(width: 1400, height: 800)
        .preferredColorScheme(.dark)
}
