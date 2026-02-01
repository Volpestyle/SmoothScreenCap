import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    @State private var availableSources: [CaptureSource] = [
        .display(name: "Built-in Retina Display", id: "1"),
        .display(name: "External Display", id: "2"),
        .window(name: "Xcode", id: "xcode"),
        .window(name: "Safari", id: "safari"),
        .window(name: "Finder", id: "finder"),
        .region
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Left panel - Source selection
            VStack(alignment: .leading, spacing: 0) {
                SidebarSectionHeader(title: "CAPTURE SOURCE")

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(availableSources) { source in
                            SourceOptionRow(
                                source: source,
                                isSelected: appState.selectedSource == source
                            ) {
                                appState.selectedSource = source
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(width: 280)
            .background(Color(white: 0.06))

            // Center - Preview area
            VStack(spacing: 0) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )

                    if let source = appState.selectedSource {
                        VStack(spacing: 16) {
                            Image(systemName: source.icon)
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("Preview: \(source.name)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)

                            Text("Recording will capture this source")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
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
                                    .fill(appState.selectedSource != nil ? Color(white: 0.15) : Color(white: 0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(appState.selectedSource != nil ? Color.white.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.selectedSource == nil)
                        .opacity(appState.selectedSource == nil ? 0.5 : 1.0)
                    }
                }
                .padding(24)
                .background(Color(white: 0.06))
            }
            .frame(maxWidth: .infinity)

            // Right panel - Settings
            VStack(alignment: .leading, spacing: 0) {
                SidebarSectionHeader(title: "AUDIO")

                VStack(spacing: 12) {
                    ToggleRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        subtitle: "MacBook Pro Microphone",
                        isOn: $appState.micEnabled
                    )

                    ToggleRow(
                        icon: "speaker.wave.2.fill",
                        title: "System Audio",
                        subtitle: "Capture app sounds",
                        isOn: $appState.systemAudioEnabled
                    )
                }
                .padding(16)

                Divider()
                    .background(Color.white.opacity(0.06))

                SidebarSectionHeader(title: "VIDEO")

                VStack(spacing: 12) {
                    ToggleRow(
                        icon: "video.fill",
                        title: "Webcam",
                        subtitle: "FaceTime HD Camera",
                        isOn: $appState.webcamEnabled
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

                Spacer()

                // Hotkey reminder
                VStack(alignment: .leading, spacing: 8) {
                    Text("HOTKEYS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

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
            .frame(width: 280)
            .background(Color(white: 0.06))
        }
        .background(Color(white: 0.04))
    }
}

struct SourceOptionRow: View {
    let source: CaptureSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: source.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)

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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
}

#Preview {
    RecordingView()
        .environmentObject(AppState())
        .frame(width: 1400, height: 800)
        .preferredColorScheme(.dark)
}
