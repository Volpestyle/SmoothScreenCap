import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var hoveredProject: Project?

    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return appState.recentProjects
        }
        return appState.recentProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(alignment: .leading, spacing: 0) {
                // Toolbar
                HStack(spacing: 16) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search projects...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)

                    Spacer()

                    // New recording button
                    Button {
                        withAnimation { appState.currentSection = .recording }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("NEW RECORDING")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)

                Divider()
                    .background(Color.white.opacity(0.06))

                // Projects grid
                ScrollView {
                    if filteredProjects.isEmpty {
                        EmptyLibraryState()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 20)], spacing: 20) {
                            ForEach(filteredProjects) { project in
                                ProjectCard(
                                    project: project,
                                    isHovered: hoveredProject == project
                                )
                                .onTapGesture {
                                    appState.openProject(project)
                                }
                                .onHover { isHovered in
                                    hoveredProject = isHovered ? project : nil
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Right sidebar - Quick info
            VStack(alignment: .leading, spacing: 0) {
                SidebarSectionHeader(title: "QUICK STATS")

                VStack(spacing: 16) {
                    StatRow(label: "TOTAL PROJECTS", value: "\(appState.recentProjects.count)")
                    StatRow(label: "TOTAL DURATION", value: formatTotalDuration())
                    StatRow(label: "DISK USAGE", value: "2.4 GB")
                }
                .padding(16)

                Divider()
                    .background(Color.white.opacity(0.06))

                SidebarSectionHeader(title: "KEYBOARD SHORTCUTS")

                VStack(alignment: .leading, spacing: 12) {
                    ShortcutRow(keys: "⌘ R", action: "Start recording")
                    ShortcutRow(keys: "⌘ .", action: "Stop recording")
                    ShortcutRow(keys: "⌘ E", action: "Export project")
                    ShortcutRow(keys: "Space", action: "Play/Pause")
                }
                .padding(16)

                Spacer()
            }
            .frame(width: 260)
            .background(Color(white: 0.06))
        }
        .background(Color(white: 0.04))
    }

    private func formatTotalDuration() -> String {
        let total = appState.recentProjects.reduce(0) { $0 + $1.duration }
        let minutes = Int(total) / 60
        return "\(minutes) min"
    }
}

struct ProjectCard: View {
    let project: Project
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [project.thumbnailColor.opacity(0.3), project.thumbnailColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(isHovered ? 0.9 : 0.3))
            }
            .frame(height: 160)
            .overlay(alignment: .topTrailing) {
                Text(formatDuration(project.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(8)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct EmptyLibraryState: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No projects yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            Text("Start your first recording to create a project")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button {
                appState.currentSection = .recording
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                    Text("NEW RECORDING")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02))
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)

            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(AppState())
        .frame(width: 1400, height: 800)
        .preferredColorScheme(.dark)
}
