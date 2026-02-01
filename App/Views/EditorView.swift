import SwiftUI

struct EditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(spacing: 0) {
                // Preview area
                PreviewPanel()
                    .frame(maxWidth: .infinity)

                // Right sidebar
                EditorSidebar()
                    .frame(width: 300)
            }

            // Timeline area
            TimelinePanel()
                .frame(height: 200)
        }
        .background(Color(white: 0.04))
    }
}

struct PreviewPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Preview header
            HStack {
                if let project = appState.currentProject {
                    Text(project.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 8) {
                    Button {
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("100%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.06))

            // Preview canvas
            ZStack {
                Color(white: 0.08)

                // Mock video preview
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .padding(40)

                // Cursor overlay indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .offset(x: 50, y: 30)
            }

            // Playback controls
            PlaybackControls()
        }
    }
}

struct PlaybackControls: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Time display
            Text(formatTime(appState.currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 60, alignment: .leading)

            Spacer()

            // Transport controls
            HStack(spacing: 16) {
                Button {
                    appState.currentTime = 0
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.currentTime = max(0, appState.currentTime - 5)
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.isPlaying.toggle()
                } label: {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.currentTime += 5
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    if let project = appState.currentProject {
                        appState.currentTime = project.duration
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Total duration
            if let project = appState.currentProject {
                Text(formatTime(project.duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.06))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct EditorSidebar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(EditorSidebarTab.allCases, id: \.self) { tab in
                    Button {
                        appState.selectedSidebarTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue.prefix(4).uppercased())
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(appState.selectedSidebarTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            appState.selectedSidebarTab == tab ? Color.white.opacity(0.08) : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(white: 0.06))

            Divider()
                .background(Color.white.opacity(0.06))

            // Tab content
            ScrollView {
                switch appState.selectedSidebarTab {
                case .background:
                    BackgroundTab()
                case .cursor:
                    CursorTab()
                case .zoom:
                    ZoomTab()
                case .audio:
                    AudioTab()
                case .export:
                    ExportTab()
                }
            }
        }
        .background(Color(white: 0.06))
    }
}

struct BackgroundTab: View {
    @State private var backgroundColor = Color.black
    @State private var padding: Double = 48
    @State private var cornerRadius: Double = 12
    @State private var shadowEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("COLOR")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach([Color.black, Color(white: 0.1), Color.blue.opacity(0.8), Color.purple.opacity(0.8), Color.green.opacity(0.8)], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(backgroundColor == color ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                backgroundColor = color
                            }
                    }
                }
            }

            // Padding slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PADDING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(padding))px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $padding, in: 0...100)
                    .tint(.white)
            }

            // Corner radius
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CORNERS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(cornerRadius))px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $cornerRadius, in: 0...32)
                    .tint(.white)
            }

            // Shadow toggle
            Toggle(isOn: $shadowEnabled) {
                Text("DROP SHADOW")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
        }
        .padding(16)
    }
}

struct CursorTab: View {
    @State private var cursorSize: Double = 1.0
    @State private var smoothingEnabled = true
    @State private var hideWhenIdle = true
    @State private var idleTimeout: Double = 2.0
    @State private var clickHighlight = true
    @State private var clickSound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cursor size
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SIZE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", cursorSize))x")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $cursorSize, in: 0.5...3.0)
                    .tint(.white)
            }

            // Smoothing toggle
            Toggle(isOn: $smoothingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SMOOTHING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("One Euro filter")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)

            Divider()
                .background(Color.white.opacity(0.06))

            // Hide when idle
            Toggle(isOn: $hideWhenIdle) {
                Text("HIDE WHEN IDLE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)

            if hideWhenIdle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TIMEOUT")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", idleTimeout))s")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $idleTimeout, in: 0.5...5.0)
                        .tint(.white)
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))

            // Click effects
            Toggle(isOn: $clickHighlight) {
                Text("CLICK HIGHLIGHT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)

            Toggle(isOn: $clickSound) {
                Text("CLICK SOUND")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
        }
        .padding(16)
    }
}

struct ZoomTab: View {
    @State private var autoZoomEnabled = true
    @State private var zoomLevel: Double = 2.0
    @State private var transitionDuration: Double = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $autoZoomEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUTO-ZOOM")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Zoom to click locations")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)

            if autoZoomEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ZOOM LEVEL")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", zoomLevel))x")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $zoomLevel, in: 1.2...4.0)
                        .tint(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TRANSITION")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.2f", transitionDuration))s")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $transitionDuration, in: 0.1...1.0)
                        .tint(.white)
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))

            Text("ZOOM SEGMENTS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("Edit zoom segments in the timeline below")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

struct AudioTab: View {
    @State private var micVolume: Double = 1.0
    @State private var systemVolume: Double = 0.8
    @State private var normalizeAudio = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mic volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("MICROPHONE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(micVolume * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $micVolume, in: 0...1)
                    .tint(.white)
            }

            // System audio volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("SYSTEM AUDIO")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(systemVolume * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $systemVolume, in: 0...1)
                    .tint(.white)
            }

            Divider()
                .background(Color.white.opacity(0.06))

            Toggle(isOn: $normalizeAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NORMALIZE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Auto-adjust levels")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
    }
}

struct ExportTab: View {
    @State private var selectedResolution = "1080p"
    @State private var selectedFPS = "60"
    @State private var quality: Double = 0.8

    let resolutions = ["720p", "1080p", "1440p", "2160p"]
    let frameRates = ["30", "60"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Resolution
            VStack(alignment: .leading, spacing: 8) {
                Text("RESOLUTION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(resolutions, id: \.self) { res in
                        Button {
                            selectedResolution = res
                        } label: {
                            Text(res)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(selectedResolution == res ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedResolution == res ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Frame rate
            VStack(alignment: .leading, spacing: 8) {
                Text("FRAME RATE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(frameRates, id: \.self) { fps in
                        Button {
                            selectedFPS = fps
                        } label: {
                            Text("\(fps) FPS")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(selectedFPS == fps ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedFPS == fps ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Quality slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QUALITY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(quality * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $quality, in: 0.5...1.0)
                    .tint(.white)
            }

            Spacer()
                .frame(height: 20)

            // Export buttons
            VStack(spacing: 12) {
                Button {
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("EXPORT MP4")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(.plain)

                Button {
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("COPY TO CLIPBOARD")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

struct TimelinePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var scrubberPosition: CGFloat = 0.2

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.06))

            // Timeline header
            HStack(spacing: 16) {
                Text("TIMELINE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Snap toggle
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 10))
                    Text("SNAP")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)

                // Zoom controls
                HStack(spacing: 8) {
                    Button {} label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("FIT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.06))

            // Timeline tracks
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    VStack(spacing: 8) {
                        // Clip track (yellow)
                        TimelineTrack(
                            label: "CLIP",
                            color: .yellow,
                            segments: [
                                TimelineSegment(start: 0, end: 0.3, label: "Intro"),
                                TimelineSegment(start: 0.35, end: 0.7, label: "Main"),
                                TimelineSegment(start: 0.75, end: 1.0, label: "Outro")
                            ]
                        )

                        // Zoom track (purple)
                        TimelineTrack(
                            label: "ZOOM",
                            color: .purple,
                            segments: [
                                TimelineSegment(start: 0.1, end: 0.25, label: "2x"),
                                TimelineSegment(start: 0.4, end: 0.55, label: "1.5x"),
                                TimelineSegment(start: 0.8, end: 0.9, label: "2x")
                            ]
                        )

                        // Audio waveform track
                        TimelineTrack(
                            label: "AUDIO",
                            color: .green,
                            segments: [],
                            showWaveform: true
                        )
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)

                    // Playhead
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: 60 + scrubberPosition * (geo.size.width - 120))

                    // Time labels
                    VStack {
                        HStack {
                            Text("0:00")
                            Spacer()
                            if let project = appState.currentProject {
                                Text(formatTime(project.duration / 2))
                                Spacer()
                                Text(formatTime(project.duration))
                            }
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 60)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .background(Color(white: 0.04))
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TimelineSegment: Identifiable {
    let id = UUID()
    let start: CGFloat
    let end: CGFloat
    let label: String
}

struct TimelineTrack: View {
    let label: String
    let color: Color
    let segments: [TimelineSegment]
    var showWaveform: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.03))

                    if showWaveform {
                        // Fake waveform
                        HStack(spacing: 2) {
                            ForEach(0..<60, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(color.opacity(0.6))
                                    .frame(width: 3, height: CGFloat.random(in: 8...28))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                    } else {
                        // Segments
                        ForEach(segments) { segment in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(color.opacity(0.6), lineWidth: 1)
                                )
                                .overlay(
                                    Text(segment.label)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(color)
                                )
                                .frame(width: (segment.end - segment.start) * geo.size.width)
                                .offset(x: segment.start * geo.size.width)
                        }
                    }
                }
            }
            .frame(height: 36)
        }
    }
}

#Preview {
    EditorView()
        .environmentObject({
            let state = AppState()
            state.currentProject = Project(name: "Test Project", duration: 124.5, createdAt: Date())
            return state
        }())
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
