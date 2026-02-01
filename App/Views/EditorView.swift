import SwiftUI
import AppKit
import MetalKit
import ProjectModel
import TimeMapping
import ExportEngine
import Rendering

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
                .frame(height: 220)
        }
        .background(Color(white: 0.04))
    }
}

struct PreviewPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            // Preview header
            HStack {
                if let project = appState.currentProject {
                    Text(appState.currentProjectURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    if project.edit.cuts.count > 0 || project.edit.speedSegments.count > 0 {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(project.edit.cuts.count) cuts, \(project.edit.speedSegments.count) speed changes")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
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
            GeometryReader { geo in
                let previewInset: CGFloat = 40
                let previewSize = CGSize(
                    width: max(1, geo.size.width - previewInset * 2),
                    height: max(1, geo.size.height - previewInset * 2)
                )
                let previewPixelSize = CGSize(
                    width: previewSize.width * displayScale,
                    height: previewSize.height * displayScale
                )
                ZStack {
                    Color(white: 0.08)

                    if appState.currentProject != nil {
                        // Live Metal preview
                        if appState.isLoadingPreview {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else if let frame = appState.currentPreviewFrame,
                                  let renderer = appState.previewRenderer {
                            MetalPreviewView(renderer: renderer, frame: frame)
                                .frame(width: previewSize.width, height: previewSize.height)
                                .cornerRadius(8)
                        } else {
                            // Fallback placeholder while loading
                            PreviewPlaceholder()
                                .frame(width: previewSize.width, height: previewSize.height)
                        }

                        // Current zoom indicator
                        if let activeZoom = activeZoomSegment {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.magnifyingglass")
                                            .font(.system(size: 10))
                                        Text("\(String(format: "%.1f", activeZoom.scale ?? 1.0))x")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.8))
                                    .cornerRadius(4)
                                    .padding(16)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "film")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("No project loaded")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .onAppear {
                    appState.previewOutputSize = previewPixelSize
                    Task {
                        await appState.updatePreviewFrame(outputSize: previewPixelSize)
                    }
                }
                .onChange(of: previewPixelSize) { newValue in
                    appState.previewOutputSize = newValue
                    Task {
                        await appState.updatePreviewFrame(outputSize: newValue)
                    }
                }
            }

            // Playback controls
            PlaybackControls()
        }
    }

    private var activeZoomSegment: ZoomSegment? {
        guard let sourceTime = appState.currentSourceTime else { return nil }
        return appState.zoomSegments.first { segment in
            sourceTime >= segment.start && sourceTime <= segment.end
        }
    }

}

/// Fallback placeholder shown while preview is loading
struct PreviewPlaceholder: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let project = appState.currentProject {
            let bg = project.edit.background

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: bg.cornerRadius ?? 12)
                    .fill(backgroundFill(for: bg))
                    .aspectRatio(16/9, contentMode: .fit)
                    .shadow(
                        color: .black.opacity(bg.shadow?.opacity ?? 0.5),
                        radius: bg.shadow?.radius ?? 20,
                        x: bg.shadow?.x ?? 0,
                        y: bg.shadow?.y ?? 10
                    )

                // Screen content placeholder
                RoundedRectangle(cornerRadius: max((bg.cornerRadius ?? 12) - 4, 0))
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .padding(bg.padding ?? 48)

                // Loading indicator
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading preview...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func backgroundFill(for bg: Background) -> some ShapeStyle {
        switch bg.type {
        case .color:
            return AnyShapeStyle(Color(hex: bg.color ?? "#000000") ?? .black)
        case .gradient:
            let startColor = Color(hex: bg.gradient?.startColor ?? "#1a1a2e") ?? .black
            let endColor = Color(hex: bg.gradient?.endColor ?? "#16213e") ?? .black
            return AnyShapeStyle(LinearGradient(
                colors: [startColor, endColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .image:
            return AnyShapeStyle(Color.black)
        }
    }
}

struct PlaybackControls: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Time display (output time)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(appState.currentTime))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                if let sourceTime = appState.currentSourceTime {
                    Text("src: \(formatTime(sourceTime))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Transport controls
            HStack(spacing: 16) {
                Button {
                    appState.seekToStart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.skipBackward()
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.togglePlayback()
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
                    appState.skipForward()
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.seekToEnd()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Total duration
            Text(formatTime(appState.outputDuration))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.06))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", minutes, seconds, frames)
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
    @EnvironmentObject var appState: AppState

    @State private var backgroundType: Background.BackgroundType = .color
    @State private var backgroundColor = "#000000"
    @State private var gradientEndColor = "#16213e"
    @State private var gradientAngle: Double = 135
    @State private var padding: Double = 48
    @State private var cornerRadius: Double = 12
    @State private var shadowEnabled = true
    @State private var shadowRadius: Double = 20
    @State private var shadowY: Double = 10
    @State private var shadowOpacity: Double = 0.5

    private let colorPresets = ["#000000", "#1a1a2e", "#0f3460", "#533483", "#16213e", "#2d132c", "#ee4540", "#c72c41"]
    private let gradientPresets: [(String, String, Double)] = [
        ("#1a1a2e", "#16213e", 135),
        ("#0f3460", "#533483", 45),
        ("#2d132c", "#ee4540", 180),
        ("#000000", "#434343", 90)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Background type
            VStack(alignment: .leading, spacing: 8) {
                Text("TYPE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach([("Color", Background.BackgroundType.color), ("Gradient", Background.BackgroundType.gradient)], id: \.0) { item in
                        Button {
                            backgroundType = item.1
                            updateBackground()
                            saveBackground()
                        } label: {
                            Text(item.0)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(backgroundType == item.1 ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(backgroundType == item.1 ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if backgroundType == .color {
                // Color picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("COLOR")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 8) {
                        ForEach(colorPresets, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .black)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(backgroundColor == hex ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    backgroundColor = hex
                                    updateBackground()
                                    saveBackground()
                                }
                        }
                    }
                }
            } else {
                // Gradient controls
                VStack(alignment: .leading, spacing: 12) {
                    // Gradient presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRESETS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(gradientPresets.indices, id: \.self) { index in
                                let preset = gradientPresets[index]
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: preset.0) ?? .black, Color(hex: preset.1) ?? .black],
                                            startPoint: gradientStartPoint(angle: preset.2),
                                            endPoint: gradientEndPoint(angle: preset.2)
                                        )
                                    )
                                    .frame(width: 48, height: 32)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(
                                                backgroundColor == preset.0 && gradientEndColor == preset.1 ? Color.white : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                    .onTapGesture {
                                        backgroundColor = preset.0
                                        gradientEndColor = preset.1
                                        gradientAngle = preset.2
                                        updateBackground()
                                        saveBackground()
                                    }
                            }
                        }
                    }

                    // Start color
                    VStack(alignment: .leading, spacing: 8) {
                        Text("START COLOR")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(colorPresets, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex) ?? .black)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(backgroundColor == hex ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            backgroundColor = hex
                                            updateBackground()
                                            saveBackground()
                                        }
                                }
                            }
                        }
                    }

                    // End color
                    VStack(alignment: .leading, spacing: 8) {
                        Text("END COLOR")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(colorPresets, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex) ?? .black)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(gradientEndColor == hex ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            gradientEndColor = hex
                                            updateBackground()
                                            saveBackground()
                                        }
                                }
                            }
                        }
                    }

                    // Angle slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ANGLE")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(gradientAngle))°")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Slider(value: $gradientAngle, in: 0...360) { editing in
                                updateBackground()
                                if !editing { saveBackground() }
                            }
                            .tint(.white)

                            // Angle preview
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: backgroundColor) ?? .black, Color(hex: gradientEndColor) ?? .black],
                                        startPoint: gradientStartPoint(angle: gradientAngle),
                                        endPoint: gradientEndPoint(angle: gradientAngle)
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .overlay(
                                    // Direction indicator
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .rotationEffect(.degrees(gradientAngle))
                                )
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))

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

                Slider(value: $padding, in: 0...120) { editing in
                    updateBackground()
                    if !editing { saveBackground() }
                }
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

                Slider(value: $cornerRadius, in: 0...48) { editing in
                    updateBackground()
                    if !editing { saveBackground() }
                }
                .tint(.white)
            }

            Divider()
                .background(Color.white.opacity(0.06))

            // Shadow section
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $shadowEnabled) {
                    Text("DROP SHADOW")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .onChange(of: shadowEnabled) { _, _ in
                    updateBackground()
                    saveBackground()
                }

                if shadowEnabled {
                    // Shadow radius
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("BLUR")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(Int(shadowRadius))px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Slider(value: $shadowRadius, in: 0...60) { editing in
                            updateBackground()
                            if !editing { saveBackground() }
                        }
                        .tint(.white.opacity(0.5))
                    }

                    // Shadow offset Y
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("OFFSET Y")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(Int(shadowY))px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Slider(value: $shadowY, in: 0...40) { editing in
                            updateBackground()
                            if !editing { saveBackground() }
                        }
                        .tint(.white.opacity(0.5))
                    }

                    // Shadow opacity
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("OPACITY")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(Int(shadowOpacity * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Slider(value: $shadowOpacity, in: 0...1) { editing in
                            updateBackground()
                            if !editing { saveBackground() }
                        }
                        .tint(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            loadFromProject()
        }
    }

    private func loadFromProject() {
        guard let project = appState.currentProject else { return }
        let bg = project.edit.background
        backgroundType = bg.type
        backgroundColor = bg.color ?? "#000000"
        gradientEndColor = bg.gradient?.endColor ?? "#16213e"
        gradientAngle = bg.gradient?.angle ?? 135
        padding = bg.padding ?? 48
        cornerRadius = bg.cornerRadius ?? 12
        shadowEnabled = bg.shadow != nil
        shadowRadius = bg.shadow?.radius ?? 20
        shadowY = bg.shadow?.y ?? 10
        shadowOpacity = bg.shadow?.opacity ?? 0.5
    }

    private func updateBackground() {
        let shadow = shadowEnabled ? Background.Shadow(radius: shadowRadius, x: 0, y: shadowY, color: "#000000", opacity: shadowOpacity) : nil
        let gradient = backgroundType == .gradient ? Background.Gradient(startColor: backgroundColor, endColor: gradientEndColor, angle: gradientAngle) : nil

        let background = Background(
            type: backgroundType,
            color: backgroundColor,
            gradient: gradient,
            padding: padding,
            cornerRadius: cornerRadius,
            shadow: shadow
        )
        appState.updateBackground(background)

        // Trigger live preview update
        Task {
            await appState.updatePreviewFrame()
        }
    }

    private func saveBackground() {
        appState.saveCurrentProject()
    }

    private func gradientStartPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private func gradientEndPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }
}

struct CursorTab: View {
    @EnvironmentObject var appState: AppState

    @State private var cursorStyle: Motion.Style = .mellow
    @State private var smoothingEnabled = true
    @State private var hideWhenIdle = true
    @State private var clickHighlight = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cursor motion style
            VStack(alignment: .leading, spacing: 8) {
                Text("MOTION STYLE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach([Motion.Style.slow, .mellow, .quick, .rapid], id: \.self) { style in
                        Button {
                            cursorStyle = style
                            updateMotion()
                        } label: {
                            Text(style.rawValue.capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(cursorStyle == style ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(cursorStyle == style ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(styleDescription(cursorStyle))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .background(Color.white.opacity(0.06))

            // Smoothing toggle
            Toggle(isOn: $smoothingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SMOOTHING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("One Euro filter for natural motion")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)

            // Hide when idle
            Toggle(isOn: $hideWhenIdle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HIDE WHEN IDLE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Fade out after 2 seconds")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)

            Divider()
                .background(Color.white.opacity(0.06))

            // Click effects
            Toggle(isOn: $clickHighlight) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLICK HIGHLIGHT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Visual feedback on clicks")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .onAppear {
            loadFromProject()
        }
    }

    private func styleDescription(_ style: Motion.Style) -> String {
        switch style {
        case .slow: return "Smooth, cinematic cursor movement"
        case .mellow: return "Balanced smoothing (recommended)"
        case .quick: return "Responsive with light smoothing"
        case .rapid: return "Near real-time cursor tracking"
        }
    }

    private func loadFromProject() {
        guard let project = appState.currentProject else { return }
        cursorStyle = project.edit.motion.cursorStyle ?? .mellow
    }

    private func updateMotion() {
        guard let project = appState.currentProject else { return }
        let motion = Motion(
            cursorStyle: cursorStyle,
            zoomStyle: project.edit.motion.zoomStyle,
            spring: project.edit.motion.spring
        )
        appState.updateMotion(motion)
    }
}

struct ZoomTab: View {
    @EnvironmentObject var appState: AppState
    @State private var zoomLevel: Double = 2.0
    @State private var transitionDuration: Double = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Zoom segments count
            HStack {
                Text("ZOOM SEGMENTS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.zoomSegments.count)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if !appState.zoomSegments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(appState.zoomSegments.enumerated()), id: \.offset) { index, segment in
                        ZoomSegmentRow(index: index, segment: segment)
                            .environmentObject(appState)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DEFAULT ZOOM")
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

            Divider()
                .background(Color.white.opacity(0.06))

            Text("Edit zoom segments in the timeline below. Click and drag to reposition.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

struct ZoomSegmentRow: View {
    @EnvironmentObject var appState: AppState
    let index: Int
    let segment: ZoomSegment
    @State private var isHovered = false
    @State private var isEditing = false

    var body: some View {
        HStack {
            Circle()
                .fill(Color.purple)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatTime(segment.start)) - \(formatTime(segment.end))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                Text("\(String(format: "%.1f", segment.scale ?? 1.0))x • \(segment.mode.rawValue)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isHovered || isEditing {
                HStack(spacing: 4) {
                    // Scale adjustment buttons
                    Button {
                        adjustScale(delta: -0.5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(String(format: "%.1f", segment.scale ?? 1.0))x")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.purple)
                        .frame(width: 30)

                    Button {
                        adjustScale(delta: 0.5)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 12)

                    Button {
                        deleteSegment()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(isHovered ? 0.06 : 0.03))
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func adjustScale(delta: Double) {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count else { return }

        let currentScale = project.edit.zoomSegments[index].scale ?? 1.0
        let newScale = max(1.0, min(5.0, currentScale + delta))
        project.edit.zoomSegments[index].scale = newScale
        appState.currentProject = project
        appState.saveCurrentProject()
    }

    private func deleteSegment() {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count else { return }

        project.edit.zoomSegments.remove(at: index)
        appState.currentProject = project
        appState.saveCurrentProject()
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct AudioTab: View {
    @EnvironmentObject var appState: AppState
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

                Slider(value: $micVolume, in: 0...1) { editing in
                    updateAudioSettings()
                    if !editing { saveAudioSettings() }
                }
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

                Slider(value: $systemVolume, in: 0...1) { editing in
                    updateAudioSettings()
                    if !editing { saveAudioSettings() }
                }
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
            .onChange(of: normalizeAudio) { _, _ in
                updateAudioSettings()
                saveAudioSettings()
            }
        }
        .padding(16)
        .onAppear {
            loadFromProject()
        }
    }

    private func loadFromProject() {
        guard let settings = appState.currentProject?.edit.audioSettings else { return }
        micVolume = settings.microphoneVolume
        systemVolume = settings.systemAudioVolume
        normalizeAudio = settings.normalizeAudio
    }

    private func updateAudioSettings() {
        guard var project = appState.currentProject else { return }
        project.edit.audioSettings = AudioSettings(
            microphoneVolume: micVolume,
            systemAudioVolume: systemVolume,
            normalizeAudio: normalizeAudio
        )
        appState.currentProject = project
    }

    private func saveAudioSettings() {
        appState.saveCurrentProject()
    }
}

struct ExportTab: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPresetIndex = 0
    @State private var quality: Double = 0.8
    @State private var showingSavePanel = false

    var presets: [ExportPreset] {
        appState.currentProject?.edit.exportPresets ?? []
    }

    var selectedPreset: ExportPreset? {
        guard !presets.isEmpty, selectedPresetIndex < presets.count else { return nil }
        return presets[selectedPresetIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Export status
            if appState.isExporting {
                exportingView
            } else if let successURL = appState.exportSuccess {
                exportSuccessView(url: successURL)
            } else if let error = appState.exportError {
                exportErrorView(message: error)
            }

            // Presets
            if !presets.isEmpty && !appState.isExporting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRESET")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                            Button {
                                selectedPresetIndex = index
                            } label: {
                                HStack {
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Text("\(preset.width)x\(preset.height) @ \(Int(preset.fps))fps")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(selectedPresetIndex == index ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedPresetIndex == index ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Quality slider
            if !appState.isExporting {
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
            }

            // Output info
            if let preset = selectedPreset, !appState.isExporting {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OUTPUT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("\(preset.width)x\(preset.height) • \(Int(preset.fps)) FPS • \(preset.codec?.rawValue.uppercased() ?? "H264")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("Duration: \(formatDuration(appState.outputDuration))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
            }

            Spacer()
                .frame(height: 20)

            // Export buttons
            if !appState.isExporting {
                VStack(spacing: 12) {
                    Button {
                        showSavePanel()
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
                    .disabled(selectedPreset == nil)

                    Button {
                        exportToDefaultLocation()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("QUICK EXPORT")
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
                    .disabled(selectedPreset == nil)

                    Text("Quick export saves to ~/Movies/")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .onChange(of: appState.isExporting) { _, isExporting in
            if !isExporting {
                // Clear success/error after a delay if user navigates away
            }
        }
    }

    private var exportingView: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: appState.exportProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: appState.exportProgress)

                Text("\(Int(appState.exportProgress * 100))%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)

            Text("EXPORTING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("Processing video frames...")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * appState.exportProgress)
                            .animation(.linear(duration: 0.1), value: appState.exportProgress)
                    }
                }
                .frame(height: 8)

                Text("\(Int(appState.exportProgress * 100))% complete")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func exportSuccessView(url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("EXPORT COMPLETE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)

            Text(url.lastPathComponent)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                } label: {
                    Text("REVEAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.clearExportState()
                } label: {
                    Text("DISMISS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }

    private func exportErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            Text("EXPORT FAILED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                appState.clearExportState()
            } label: {
                Text("DISMISS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private func showSavePanel() {
        guard let preset = selectedPreset else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(appState.currentProjectName)_\(preset.name).mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK, let url = panel.url {
            appState.startExport(preset: preset, outputURL: url)
        }
    }

    private func exportToDefaultLocation() {
        guard let preset = selectedPreset else { return }
        appState.exportToDefaultLocation(preset: preset)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TimelinePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var isDraggingScrubber = false
    @State private var selectedClipIndex: Int?
    @State private var selectedZoomIndex: Int?
    @State private var selectedSpeedIndex: Int?
    @State private var snapEnabled = true
    @State private var showCutMenu = false
    @State private var cutMenuPosition: CGFloat = 0
    @State private var timelineScale: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.06))

            // Timeline header
            HStack(spacing: 16) {
                Text("TIMELINE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Edit info
                if let project = appState.currentProject {
                    Text("\(project.edit.cuts.count) cuts • \(project.edit.zoomSegments.count) zooms • \(project.edit.speedSegments.count) speed")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Add cut button
                Button {
                    addCutAtPlayhead()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.system(size: 10))
                        Text("CUT")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Add cut at playhead (C)")

                // Add zoom button
                Button {
                    addZoomAtPlayhead()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 10))
                        Text("ZOOM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Add zoom segment (Z)")

                // Snap toggle
                Button {
                    snapEnabled.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 10))
                        Text("SNAP")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(snapEnabled ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // Zoom controls
                HStack(spacing: 8) {
                    Button {
                        timelineScale = max(0.5, timelineScale - 0.25)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        timelineScale = 1.0
                    } label: {
                        Text("FIT")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        timelineScale = min(4.0, timelineScale + 0.25)
                    } label: {
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
                let trackWidth = (geo.size.width - 120) * timelineScale
                let duration = appState.currentProject?.assets.screen.duration ?? 1
                let playheadNormalized = appState.outputDuration > 0 ? appState.currentTime / appState.outputDuration : 0
                let allEdges = collectAllSegmentEdges(duration: duration)

                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        VStack(spacing: 8) {
                            // Clip track (yellow) - shows kept portions
                            TimelineTrack(
                                label: "CLIP",
                                color: .yellow,
                                segments: buildClipSegments(duration: duration, selectedIndex: selectedClipIndex),
                                trackWidth: trackWidth,
                                trackType: .clip,
                                snapEnabled: snapEnabled,
                                playheadPosition: playheadNormalized,
                                allSegmentEdges: allEdges,
                                onSegmentTap: { index in
                                    selectedClipIndex = selectedClipIndex == index ? nil : index
                                    selectedZoomIndex = nil
                                    selectedSpeedIndex = nil
                                },
                                onAddSegment: { normalized in
                                    let time = normalized * duration
                                    addCutAtTime(time)
                                },
                                onResizeStart: { index, newStart in
                                    resizeClipSegmentStart(index: index, newStart: newStart * duration)
                                },
                                onResizeEnd: { index, newEnd in
                                    resizeClipSegmentEnd(index: index, newEnd: newEnd * duration)
                                },
                                onDragEnded: {
                                    saveAfterDrag()
                                }
                            )

                            // Zoom track (purple)
                            TimelineTrack(
                                label: "ZOOM",
                                color: .purple,
                                segments: buildZoomSegments(duration: duration, selectedIndex: selectedZoomIndex),
                                trackWidth: trackWidth,
                                trackType: .zoom,
                                snapEnabled: snapEnabled,
                                playheadPosition: playheadNormalized,
                                allSegmentEdges: allEdges,
                                onSegmentTap: { index in
                                    selectedZoomIndex = selectedZoomIndex == index ? nil : index
                                    selectedClipIndex = nil
                                    selectedSpeedIndex = nil
                                },
                                onAddSegment: { normalized in
                                    let time = normalized * duration
                                    addZoomAtTime(time)
                                },
                                onResizeStart: { index, newStart in
                                    resizeZoomSegmentStart(index: index, newStart: newStart * duration)
                                },
                                onResizeEnd: { index, newEnd in
                                    resizeZoomSegmentEnd(index: index, newEnd: newEnd * duration)
                                },
                                onDragEnded: {
                                    saveAfterDrag()
                                }
                            )

                            // Speed track (orange)
                            TimelineTrack(
                                label: "SPEED",
                                color: .orange,
                                segments: buildSpeedSegments(duration: duration, selectedIndex: selectedSpeedIndex),
                                trackWidth: trackWidth,
                                trackType: .speed,
                                snapEnabled: snapEnabled,
                                playheadPosition: playheadNormalized,
                                allSegmentEdges: allEdges,
                                onSegmentTap: { index in
                                    selectedSpeedIndex = selectedSpeedIndex == index ? nil : index
                                    selectedClipIndex = nil
                                    selectedZoomIndex = nil
                                },
                                onAddSegment: { normalized in
                                    let time = normalized * duration
                                    addSpeedAtTime(time)
                                },
                                onResizeStart: { index, newStart in
                                    resizeSpeedSegmentStart(index: index, newStart: newStart * duration)
                                },
                                onResizeEnd: { index, newEnd in
                                    resizeSpeedSegmentEnd(index: index, newEnd: newEnd * duration)
                                },
                                onDragEnded: {
                                    saveAfterDrag()
                                }
                            )

                            // Audio waveform track
                            TimelineTrack(
                                label: "AUDIO",
                                color: .green,
                                segments: [],
                                trackWidth: trackWidth,
                                showWaveform: true,
                                trackType: .audio,
                                snapEnabled: snapEnabled,
                                playheadPosition: playheadNormalized,
                                allSegmentEdges: allEdges
                            )
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 16)

                        // Playhead
                        let playheadX = 60 + (appState.currentTime / appState.outputDuration) * trackWidth
                        VStack(spacing: 0) {
                            // Playhead handle
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .offset(y: -2)

                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 2)
                        }
                        .offset(x: playheadX.isNaN ? 60 : playheadX - 5)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingScrubber = true
                                    let x = value.location.x - 60
                                    let normalized = max(0, min(1, x / trackWidth))
                                    appState.seek(to: normalized * appState.outputDuration)
                                }
                                .onEnded { _ in
                                    isDraggingScrubber = false
                                }
                        )

                        // Time labels
                        VStack {
                            HStack {
                                Text("0:00")
                                Spacer()
                                Text(formatTime(duration * 0.25))
                                Spacer()
                                Text(formatTime(duration * 0.5))
                                Spacer()
                                Text(formatTime(duration * 0.75))
                                Spacer()
                                Text(formatTime(duration))
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 60)

                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: max(geo.size.width, trackWidth + 120))
                }
            }
            .background(Color(white: 0.04))

            // Selection info bar
            if selectedClipIndex != nil || selectedZoomIndex != nil || selectedSpeedIndex != nil {
                SelectionInfoBar(
                    selectedClipIndex: $selectedClipIndex,
                    selectedZoomIndex: $selectedZoomIndex,
                    selectedSpeedIndex: $selectedSpeedIndex
                )
            }
        }
    }

    // MARK: - Segment Building

    private func buildClipSegments(duration: Double, selectedIndex: Int?) -> [TimelineSegment] {
        guard duration > 0 else { return [] }

        // Build segments from cuts (show kept portions)
        let cuts = appState.cuts.sorted { $0.start < $1.start }
        var segments: [TimelineSegment] = []
        var cursor = 0.0

        for cut in cuts {
            if cut.start > cursor {
                segments.append(TimelineSegment(
                    start: cursor / duration,
                    end: cut.start / duration,
                    label: "",
                    isSelected: segments.count == selectedIndex
                ))
            }
            cursor = cut.end
        }

        if cursor < duration {
            segments.append(TimelineSegment(
                start: cursor / duration,
                end: 1.0,
                label: "",
                isSelected: segments.count == selectedIndex
            ))
        }

        // If no cuts, show full clip
        if segments.isEmpty {
            segments.append(TimelineSegment(start: 0, end: 1, label: "Full", isSelected: selectedIndex == 0))
        }

        return segments
    }

    private func buildZoomSegments(duration: Double, selectedIndex: Int?) -> [TimelineSegment] {
        return appState.zoomSegments.enumerated().map { index, segment in
            TimelineSegment(
                start: segment.start / duration,
                end: segment.end / duration,
                label: "\(String(format: "%.1f", segment.scale ?? 1.0))x",
                isSelected: index == selectedIndex
            )
        }
    }

    private func buildSpeedSegments(duration: Double, selectedIndex: Int?) -> [TimelineSegment] {
        return appState.speedSegments.enumerated().map { index, segment in
            TimelineSegment(
                start: segment.start / duration,
                end: segment.end / duration,
                label: "\(String(format: "%.1f", segment.rate))x",
                isSelected: index == selectedIndex
            )
        }
    }

    // MARK: - Edit Actions

    private func addCutAtPlayhead() {
        guard let sourceTime = appState.currentSourceTime else { return }
        addCutAtTime(sourceTime)
    }

    private func addCutAtTime(_ time: Double) {
        guard let duration = appState.currentProject?.assets.screen.duration else { return }
        // Add a 2-second cut starting at the given time
        let cutStart = max(0, time)
        let cutEnd = min(duration, time + 2.0)
        appState.addCut(start: cutStart, end: cutEnd)
    }

    private func addZoomAtPlayhead() {
        guard let sourceTime = appState.currentSourceTime else { return }
        addZoomAtTime(sourceTime)
    }

    private func addZoomAtTime(_ time: Double) {
        guard var project = appState.currentProject,
              let duration = project.assets.screen.duration else { return }

        let zoomStart = max(0, time)
        let zoomEnd = min(duration, time + 3.0)

        let newSegment = ZoomSegment(
            start: zoomStart,
            end: zoomEnd,
            mode: .manual,
            scale: 2.0
        )

        project.edit.zoomSegments.append(newSegment)
        project.edit.zoomSegments.sort { $0.start < $1.start }
        appState.currentProject = project
    }

    private func addSpeedAtTime(_ time: Double) {
        guard let duration = appState.currentProject?.assets.screen.duration else { return }
        let speedStart = max(0, time)
        let speedEnd = min(duration, time + 3.0)
        appState.addSpeedSegment(start: speedStart, end: speedEnd, rate: 2.0)
    }

    // MARK: - Segment Edge Collection for Snapping

    private func collectAllSegmentEdges(duration: Double) -> [CGFloat] {
        guard duration > 0 else { return [] }
        var edges: [CGFloat] = []

        // Collect from cuts (clip edges)
        for cut in appState.cuts {
            edges.append(cut.start / duration)
            edges.append(cut.end / duration)
        }

        // Collect from zoom segments
        for segment in appState.zoomSegments {
            edges.append(segment.start / duration)
            edges.append(segment.end / duration)
        }

        // Collect from speed segments
        for segment in appState.speedSegments {
            edges.append(segment.start / duration)
            edges.append(segment.end / duration)
        }

        return edges
    }

    // MARK: - Clip Segment Resizing

    private func resizeClipSegmentStart(index: Int, newStart: Double) {
        // Clip segments are derived from cuts - resizing a clip means adjusting adjacent cuts
        // For now, this is a no-op as clips are computed from cuts
        // TODO: Implement inverse mapping from clip to cut
    }

    private func resizeClipSegmentEnd(index: Int, newEnd: Double) {
        // Clip segments are derived from cuts - resizing a clip means adjusting adjacent cuts
        // For now, this is a no-op as clips are computed from cuts
        // TODO: Implement inverse mapping from clip to cut
    }

    // MARK: - Zoom Segment Resizing

    private func resizeZoomSegmentStart(index: Int, newStart: Double) {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count,
              project.assets.screen.duration != nil else { return }

        let minDuration = 0.1
        let currentEnd = project.edit.zoomSegments[index].end
        let clampedStart = max(0, min(newStart, currentEnd - minDuration))

        project.edit.zoomSegments[index].start = clampedStart
        appState.currentProject = project

        // Update preview during drag
        Task {
            await appState.updatePreviewFrame()
        }
    }

    private func resizeZoomSegmentEnd(index: Int, newEnd: Double) {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count,
              let duration = project.assets.screen.duration else { return }

        let minDuration = 0.1
        let currentStart = project.edit.zoomSegments[index].start
        let clampedEnd = max(currentStart + minDuration, min(newEnd, duration))

        project.edit.zoomSegments[index].end = clampedEnd
        appState.currentProject = project

        // Update preview during drag
        Task {
            await appState.updatePreviewFrame()
        }
    }

    // MARK: - Speed Segment Resizing

    private func resizeSpeedSegmentStart(index: Int, newStart: Double) {
        guard var project = appState.currentProject,
              index < project.edit.speedSegments.count,
              project.assets.screen.duration != nil else { return }

        let minDuration = 0.1
        let currentEnd = project.edit.speedSegments[index].end
        let clampedStart = max(0, min(newStart, currentEnd - minDuration))

        project.edit.speedSegments[index].start = clampedStart
        appState.currentProject = project
    }

    private func resizeSpeedSegmentEnd(index: Int, newEnd: Double) {
        guard var project = appState.currentProject,
              index < project.edit.speedSegments.count,
              let duration = project.assets.screen.duration else { return }

        let minDuration = 0.1
        let currentStart = project.edit.speedSegments[index].start
        let clampedEnd = max(currentStart + minDuration, min(newEnd, duration))

        project.edit.speedSegments[index].end = clampedEnd
        appState.currentProject = project
    }

    // MARK: - Save After Drag

    private func saveAfterDrag() {
        appState.saveCurrentProject()
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Selection Info Bar

struct SelectionInfoBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedClipIndex: Int?
    @Binding var selectedZoomIndex: Int?
    @Binding var selectedSpeedIndex: Int?

    var body: some View {
        HStack(spacing: 16) {
            if let zoomIndex = selectedZoomIndex,
               zoomIndex < appState.zoomSegments.count {
                let segment = appState.zoomSegments[zoomIndex]

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 8, height: 8)

                    Text("ZOOM \(zoomIndex + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.purple)

                    Text("\(formatTime(segment.start)) - \(formatTime(segment.end))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 16)

                    // Scale stepper
                    HStack(spacing: 4) {
                        Text("SCALE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button {
                            adjustZoomScale(index: zoomIndex, delta: -0.5)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)

                        Text("\(String(format: "%.1f", segment.scale ?? 1.0))x")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 36)

                        Button {
                            adjustZoomScale(index: zoomIndex, delta: 0.5)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    deleteZoomSegment(at: zoomIndex)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            } else if let speedIndex = selectedSpeedIndex,
                      speedIndex < appState.speedSegments.count {
                let segment = appState.speedSegments[speedIndex]

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)

                    Text("SPEED \(speedIndex + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)

                    Text("\(formatTime(segment.start)) - \(formatTime(segment.end))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 16)

                    // Quick rate presets
                    HStack(spacing: 4) {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                            Button {
                                setSpeedRate(index: speedIndex, rate: rate)
                            } label: {
                                Text("\(String(format: "%.1f", rate))x")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(abs(segment.rate - rate) < 0.01 ? .white : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(abs(segment.rate - rate) < 0.01 ? Color.orange.opacity(0.3) : Color.white.opacity(0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .frame(height: 16)

                    // Rate fine-tune stepper
                    HStack(spacing: 4) {
                        Button {
                            adjustSpeedRate(index: speedIndex, delta: -0.25)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Text("\(String(format: "%.2f", segment.rate))x")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 40)

                        Button {
                            adjustSpeedRate(index: speedIndex, delta: 0.25)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    deleteSpeedSegment(at: speedIndex)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            } else if let clipIndex = selectedClipIndex {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)

                    Text("CLIP \(clipIndex + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.yellow)

                    Text("Select a cut region to delete it")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func adjustZoomScale(index: Int, delta: Double) {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count else { return }

        let currentScale = project.edit.zoomSegments[index].scale ?? 1.0
        let newScale = max(1.0, min(5.0, currentScale + delta))
        project.edit.zoomSegments[index].scale = newScale
        appState.currentProject = project
    }

    private func deleteZoomSegment(at index: Int) {
        guard var project = appState.currentProject,
              index < project.edit.zoomSegments.count else { return }

        project.edit.zoomSegments.remove(at: index)
        appState.currentProject = project
        selectedZoomIndex = nil
    }

    private func adjustSpeedRate(index: Int, delta: Double) {
        guard var project = appState.currentProject,
              index < project.edit.speedSegments.count else { return }

        let currentRate = project.edit.speedSegments[index].rate
        let newRate = max(0.25, min(4.0, currentRate + delta))
        project.edit.speedSegments[index].rate = newRate
        appState.currentProject = project
        appState.saveCurrentProject()
    }

    private func setSpeedRate(index: Int, rate: Double) {
        guard var project = appState.currentProject,
              index < project.edit.speedSegments.count else { return }

        let newRate = max(0.25, min(4.0, rate))
        project.edit.speedSegments[index].rate = newRate
        appState.currentProject = project
        appState.saveCurrentProject()
    }

    private func deleteSpeedSegment(at index: Int) {
        guard var project = appState.currentProject,
              index < project.edit.speedSegments.count else { return }

        project.edit.speedSegments.remove(at: index)
        appState.currentProject = project
        selectedSpeedIndex = nil
    }
}

struct TimelineSegment: Identifiable {
    let id = UUID()
    let start: CGFloat
    let end: CGFloat
    let label: String
    var isSelected: Bool = false
}

enum TimelineTrackType {
    case clip
    case zoom
    case speed
    case audio
}

struct TimelineTrack: View {
    let label: String
    let color: Color
    let segments: [TimelineSegment]
    let trackWidth: CGFloat
    var showWaveform: Bool = false
    var trackType: TimelineTrackType = .clip
    var snapEnabled: Bool = true
    var playheadPosition: CGFloat = 0 // Normalized 0-1
    var allSegmentEdges: [CGFloat] = [] // All segment start/end positions for snapping
    var onSegmentTap: ((Int) -> Void)?
    var onAddSegment: ((CGFloat) -> Void)?
    var onResizeStart: ((Int, CGFloat) -> Void)? // index, new start
    var onResizeEnd: ((Int, CGFloat) -> Void)?   // index, new end
    var onDragEnded: (() -> Void)?

    @State private var hoveredSegmentIndex: Int?

    private var snapPoints: [CGFloat] {
        var points = allSegmentEdges
        points.append(playheadPosition)
        // Add common positions
        points.append(contentsOf: [0, 0.25, 0.5, 0.75, 1.0])
        return points.sorted()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: trackWidth)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalized = location.x / trackWidth
                        onAddSegment?(normalized)
                    }

                if showWaveform {
                    // Fake waveform
                    HStack(spacing: 2) {
                        ForEach(0..<Int(trackWidth / 5), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color.opacity(0.6))
                                .frame(width: 3, height: waveformHeight(for: i))
                        }
                    }
                    .frame(width: trackWidth)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
                } else {
                    // Segments
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        InteractiveSegment(
                            segment: segment,
                            index: index,
                            color: color,
                            trackWidth: trackWidth,
                            isHovered: hoveredSegmentIndex == index,
                            snapPoints: snapPoints,
                            snapEnabled: snapEnabled,
                            onTap: { onSegmentTap?(index) },
                            onResizeStart: { newStart in
                                onResizeStart?(index, newStart)
                            },
                            onResizeEnd: { newEnd in
                                onResizeEnd?(index, newEnd)
                            },
                            onDragEnded: {
                                onDragEnded?()
                            }
                        )
                        .onHover { isHovered in
                            hoveredSegmentIndex = isHovered ? index : nil
                        }
                    }
                }
            }
            .frame(height: 36)
        }
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        // Deterministic pseudo-random based on index
        let seed = Double(index) * 0.7
        return CGFloat(8 + abs(sin(seed * 3.14159) * 20))
    }
}

struct InteractiveSegment: View {
    let segment: TimelineSegment
    let index: Int
    let color: Color
    let trackWidth: CGFloat
    let isHovered: Bool
    let snapPoints: [CGFloat] // Normalized snap points (0-1)
    let snapEnabled: Bool
    let onTap: () -> Void
    let onResizeStart: (CGFloat) -> Void // Pass new normalized start position
    let onResizeEnd: (CGFloat) -> Void   // Pass new normalized end position
    let onDragEnded: () -> Void

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var dragStartPosition: CGFloat = 0
    @State private var initialStart: CGFloat = 0
    @State private var initialEnd: CGFloat = 0

    private let snapThreshold: CGFloat = 8 // pixels
    private let minimumSegmentWidth: CGFloat = 0.02 // 2% minimum width

    private var segmentWidth: CGFloat {
        max(0, (segment.end - segment.start) * trackWidth)
    }

    private func snapToNearestPoint(_ value: CGFloat) -> CGFloat {
        guard snapEnabled else { return value }
        let pixelPosition = value * trackWidth
        for snapPoint in snapPoints {
            let snapPixelPosition = snapPoint * trackWidth
            if abs(pixelPosition - snapPixelPosition) < snapThreshold {
                return snapPoint
            }
        }
        return value
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Segment body
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(segment.isSelected ? 0.5 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            color.opacity(isHovered || segment.isSelected ? 1 : 0.6),
                            lineWidth: segment.isSelected ? 2 : 1
                        )
                )
                .overlay(
                    Text(segment.label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                )
                .frame(width: segmentWidth)
                .onTapGesture {
                    onTap()
                }

            // Start handle
            if (isHovered || isDraggingStart || isDraggingEnd) && segmentWidth > 20 {
                Rectangle()
                    .fill(isDraggingStart ? color : color.opacity(0.8))
                    .frame(width: 4, height: 28)
                    .cornerRadius(2)
                    .offset(x: 2)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !isDraggingStart {
                                    isDraggingStart = true
                                    dragStartPosition = value.startLocation.x
                                    initialStart = segment.start
                                    initialEnd = segment.end
                                }
                                let delta = value.location.x - dragStartPosition
                                let normalizedDelta = delta / trackWidth
                                var newStart = initialStart + normalizedDelta
                                // Clamp to valid range (0 to end - minimum)
                                newStart = max(0, min(newStart, initialEnd - minimumSegmentWidth))
                                newStart = snapToNearestPoint(newStart)
                                // Ensure we don't go past end
                                if newStart < segment.end - minimumSegmentWidth {
                                    onResizeStart(newStart)
                                }
                            }
                            .onEnded { _ in
                                isDraggingStart = false
                                onDragEnded()
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else if !isDraggingStart {
                            NSCursor.pop()
                        }
                    }

                // End handle
                Rectangle()
                    .fill(isDraggingEnd ? color : color.opacity(0.8))
                    .frame(width: 4, height: 28)
                    .cornerRadius(2)
                    .offset(x: segmentWidth - 6)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !isDraggingEnd {
                                    isDraggingEnd = true
                                    dragStartPosition = value.startLocation.x
                                    initialStart = segment.start
                                    initialEnd = segment.end
                                }
                                let delta = value.location.x - dragStartPosition
                                let normalizedDelta = delta / trackWidth
                                var newEnd = initialEnd + normalizedDelta
                                // Clamp to valid range (start + minimum to 1)
                                newEnd = max(initialStart + minimumSegmentWidth, min(newEnd, 1.0))
                                newEnd = snapToNearestPoint(newEnd)
                                // Ensure we don't go past start
                                if newEnd > segment.start + minimumSegmentWidth {
                                    onResizeEnd(newEnd)
                                }
                            }
                            .onEnded { _ in
                                isDraggingEnd = false
                                onDragEnded()
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else if !isDraggingEnd {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .offset(x: segment.start * trackWidth)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    EditorView()
        .environmentObject({
            let state = AppState()
            return state
        }())
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
