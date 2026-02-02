import Foundation
import SwiftUI
import ProjectModel
import ProjectPackaging

final class ProjectManager {

    private let fileManager = FileManager.default

    var projectsDirectory: URL {
        let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let dir = movies.appendingPathComponent("SmoothScreenCap", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Project Discovery

    func listProjects() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.pathExtension == "smoothscreencap" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return date1 > date2
            }
    }

    // MARK: - Load / Save

    func load(from packageURL: URL) throws -> ProjectModel {
        let projectJSON = packageURL.appendingPathComponent(ProjectModel.projectFilename)
        let data = try Data(contentsOf: projectJSON)
        let project = try ProjectModel.decodeJSON(data)
        try ProjectValidator.validateOrThrow(project)
        return project
    }

    func save(_ project: ProjectModel, to packageURL: URL) throws {
        try ProjectValidator.validateOrThrow(project)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let projectJSON = packageURL.appendingPathComponent(ProjectModel.projectFilename)
        let data = try project.encodedJSON(prettyPrinted: true)
        try data.write(to: projectJSON)
    }

    func packageRecording(
        at packageURL: URL,
        assets: ProjectAssetInputs,
        options: ProjectPackagingOptions
    ) throws -> ProjectModel {
        try ProjectPackager.writePackage(
            at: packageURL,
            assets: assets,
            options: options
        )
    }

    func loadMetadata(from packageURL: URL) -> ProjectMetadata? {
        do {
            let project = try load(from: packageURL)
            let name = packageURL.deletingPathExtension().lastPathComponent
            let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .red, .cyan]
            let colorIndex = abs(project.id.hashValue) % colors.count

            var metadata = ProjectMetadata(
                name: name,
                duration: project.assets.screen.duration ?? 0,
                createdAt: project.createdAt,
                thumbnailColor: colors[colorIndex]
            )
            metadata.url = packageURL
            return metadata
        } catch {
            return nil
        }
    }

    // MARK: - Project Creation

    func newProjectURL(name: String) -> URL {
        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return projectsDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension("smoothscreencap")
    }

    // MARK: - Asset Paths

    func screenVideoURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("screen.mov")
    }

    func micAudioURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("mic.m4a")
    }

    func systemAudioURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("system.m4a")
    }

    func webcamVideoURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("webcam.mov")
    }

    func eventsURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("events.jsonl")
    }

    // MARK: - Delete

    func deleteProject(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}

// Demo project scaffolding removed (use real packages).
