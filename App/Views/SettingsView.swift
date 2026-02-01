import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("defaultMicEnabled") private var defaultMicEnabled = true
    @AppStorage("defaultSystemAudioEnabled") private var defaultSystemAudioEnabled = true
    @AppStorage("defaultAutoZoomEnabled") private var defaultAutoZoomEnabled = true
    @AppStorage("projectsDirectory") private var projectsDirectory = "~/Movies/SmoothScreenCap"
    @AppStorage("recordingHotkey") private var recordingHotkey = "⌘ R"

    var body: some View {
        TabView {
            GeneralSettingsTab(
                defaultMicEnabled: $defaultMicEnabled,
                defaultSystemAudioEnabled: $defaultSystemAudioEnabled,
                defaultAutoZoomEnabled: $defaultAutoZoomEnabled
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            RecordingSettingsTab(
                projectsDirectory: $projectsDirectory,
                recordingHotkey: $recordingHotkey
            )
            .tabItem {
                Label("Recording", systemImage: "record.circle")
            }

            ExportSettingsTab()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

            PrivacySettingsTab()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsTab: View {
    @Binding var defaultMicEnabled: Bool
    @Binding var defaultSystemAudioEnabled: Bool
    @Binding var defaultAutoZoomEnabled: Bool

    var body: some View {
        Form {
            Section("Default Recording Settings") {
                Toggle("Enable microphone by default", isOn: $defaultMicEnabled)
                Toggle("Enable system audio by default", isOn: $defaultSystemAudioEnabled)
                Toggle("Enable auto-zoom by default", isOn: $defaultAutoZoomEnabled)
            }

            Section("Appearance") {
                Text("Theme settings coming in v1.0")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct RecordingSettingsTab: View {
    @Binding var projectsDirectory: String
    @Binding var recordingHotkey: String

    var body: some View {
        Form {
            Section("Storage") {
                HStack {
                    Text("Projects folder")
                    Spacer()
                    Text(projectsDirectory)
                        .foregroundStyle(.secondary)
                    Button("Choose...") {
                        // Open folder picker
                    }
                }
            }

            Section("Hotkeys") {
                HStack {
                    Text("Start/Stop Recording")
                    Spacer()
                    Text(recordingHotkey)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            Section("Capture") {
                Toggle("Show countdown before recording", isOn: .constant(true))
                Toggle("Play sound when recording starts", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ExportSettingsTab: View {
    @AppStorage("defaultResolution") private var defaultResolution = "1080p"
    @AppStorage("defaultFPS") private var defaultFPS = 60

    var body: some View {
        Form {
            Section("Default Export Settings") {
                Picker("Resolution", selection: $defaultResolution) {
                    Text("720p").tag("720p")
                    Text("1080p").tag("1080p")
                    Text("1440p").tag("1440p")
                    Text("2160p (4K)").tag("2160p")
                }

                Picker("Frame Rate", selection: $defaultFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
            }

            Section("Codec") {
                Picker("Video Codec", selection: .constant("H.264")) {
                    Text("H.264").tag("H.264")
                    Text("HEVC (H.265)").tag("HEVC")
                }

                Text("HEVC provides smaller file sizes but may have compatibility issues with older players.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PrivacySettingsTab: View {
    @AppStorage("eventLoggingEnabled") private var eventLoggingEnabled = true
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = false

    var body: some View {
        Form {
            Section("Event Logging") {
                Toggle("Log mouse and keyboard events", isOn: $eventLoggingEnabled)

                Text("Event logging enables features like auto-zoom from clicks and cursor smoothing. Keyboard events only log timing, not key values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Crash Reporting") {
                Toggle("Send anonymous crash reports", isOn: $crashReportingEnabled)

                Text("Help improve SmoothScreenCap by sending anonymous crash data. No personal information or recording content is ever sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Clear All Projects...") {
                    // Show confirmation dialog
                }
                .foregroundStyle(.red)

                Button("Open Projects Folder") {
                    // Open in Finder
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
