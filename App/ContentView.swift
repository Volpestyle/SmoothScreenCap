import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderBar()

                switch appState.currentSection {
                case .library:
                    LibraryView()
                case .recording:
                    RecordingView()
                case .editor:
                    EditorView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct HeaderBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // App title / logo
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)

                Text("SMOOTHSCREENCAP")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)

            Divider()
                .frame(height: 24)

            // Navigation
            HStack(spacing: 4) {
                ForEach(AppState.AppSection.allCases, id: \.self) { section in
                    NavButton(
                        title: section.rawValue.uppercased(),
                        isActive: appState.currentSection == section
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.currentSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Status indicator
            if appState.isRecording {
                RecordingIndicator()
            }

            // Settings
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .frame(height: 52)
        .background(Color(white: 0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

struct NavButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct RecordingIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isBlinking = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(isBlinking ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBlinking)

            Text(formatDuration(appState.recordingDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
                )
        )
        .onAppear { isBlinking = true }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1400, height: 900)
}
