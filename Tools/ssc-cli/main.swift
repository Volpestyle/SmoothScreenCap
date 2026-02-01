import AutoZoom
import ExportEngine
import Foundation
import ProjectModel
import ProjectPackaging
import Rendering
import TimeMapping

@main
struct SSCCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        let rest = Array(args.dropFirst())
        switch command {
        case "validate":
            runValidate(rest)
        case "package":
            runPackage(rest)
        case "export":
            runExport(rest)
        case "presets":
            runPresets(rest)
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    private static func runValidate(_ args: [String]) {
        guard let packagePath = args.first else {
            print("validate requires a package path")
            return
        }
        let packageURL = URL(fileURLWithPath: packagePath)
        let projectURL = packageURL.appendingPathComponent(ProjectModel.projectFilename)
        do {
            let data = try Data(contentsOf: projectURL)
            let project = try ProjectModel.decodeJSON(data)
            var missing: [String] = []
            let screenPath = packageURL.appendingPathComponent(project.assets.screen.path)
            if !FileManager.default.fileExists(atPath: screenPath.path) {
                missing.append(project.assets.screen.path)
            }
            let eventsPath = packageURL.appendingPathComponent(project.assets.events.path)
            if !FileManager.default.fileExists(atPath: eventsPath.path) {
                missing.append(project.assets.events.path)
            }
            if let mic = project.assets.mic {
                let micPath = packageURL.appendingPathComponent(mic.path)
                if !FileManager.default.fileExists(atPath: micPath.path) {
                    missing.append(mic.path)
                }
            }
            if let system = project.assets.systemAudio {
                let systemPath = packageURL.appendingPathComponent(system.path)
                if !FileManager.default.fileExists(atPath: systemPath.path) {
                    missing.append(system.path)
                }
            }
            if let webcam = project.assets.webcam {
                let webcamPath = packageURL.appendingPathComponent(webcam.path)
                if !FileManager.default.fileExists(atPath: webcamPath.path) {
                    missing.append(webcam.path)
                }
            }

            if missing.isEmpty {
                print("OK: \(packageURL.lastPathComponent)")
                print("Duration: \(project.assets.screen.duration ?? 0) s")
                print("Version: \(project.version)")
            } else {
                print("Missing assets:")
                for path in missing {
                    print(" - \(path)")
                }
                exit(1)
            }
        } catch {
            print("Validation failed: \(error)")
            exit(1)
        }
    }

    private static func runPackage(_ args: [String]) {
        let parsed = ParsedArgs(args: args)
        guard let output = parsed.options["output"],
              let screen = parsed.options["screen"] else {
            print("package requires --output and --screen")
            return
        }

        let packageURL = URL(fileURLWithPath: output)
        let screenURL = URL(fileURLWithPath: screen)
        let systemURL = parsed.options["system"].map { URL(fileURLWithPath: $0) }
        let micURL = parsed.options["mic"].map { URL(fileURLWithPath: $0) }
        let webcamURL = parsed.options["webcam"].map { URL(fileURLWithPath: $0) }
        let eventsURL = parsed.options["events"].map { URL(fileURLWithPath: $0) }

        let appVersion = parsed.options["app-version"] ?? "0.1.0"
        let autoZoomEnabled = !parsed.flags.contains("no-auto-zoom")

        let assets = ProjectAssetInputs(
            screenVideoURL: screenURL,
            systemAudioURL: systemURL,
            microphoneAudioURL: micURL,
            webcamVideoURL: webcamURL,
            eventsURL: eventsURL
        )

        let options = ProjectPackagingOptions(
            appVersion: appVersion,
            defaults: .standard,
            autoZoomEnabled: autoZoomEnabled,
            autoZoomConfig: AutoZoom.Config(),
            outputAspectRatio: nil,
            filenames: ProjectPackageFilenames()
        )

        do {
            let project = try ProjectPackager.writePackage(
                at: packageURL,
                assets: assets,
                options: options
            )
            print("Package created at \(packageURL.path)")
            print("Project ID: \(project.id.uuidString)")
        } catch {
            print("Failed to create package: \(error)")
            exit(1)
        }
    }

    private static func runExport(_ args: [String]) {
        let parsed = ParsedArgs(args: args)
        guard let packagePath = parsed.positionals.first ?? parsed.options["project"] else {
            print("export requires a package path")
            return
        }
        guard let presetName = parsed.options["preset"] else {
            print("export requires --preset <name>")
            return
        }
        guard let output = parsed.options["output"] else {
            print("export requires --output <path>")
            return
        }

        let packageURL = URL(fileURLWithPath: packagePath)
        let projectURL = packageURL.appendingPathComponent(ProjectModel.projectFilename)
        let outputURL = URL(fileURLWithPath: output)

        do {
            let data = try Data(contentsOf: projectURL)
            let project = try ProjectModel.decodeJSON(data)
            guard let duration = project.assets.screen.duration else {
                print("Project missing screen duration")
                exit(1)
            }

            guard let preset = project.edit.exportPresets.first(where: { $0.name == presetName }) else {
                print("Preset not found: \(presetName)")
                exit(1)
            }

            let mapping = TimeMapping(
                sourceDuration: duration,
                cuts: project.edit.cuts,
                speedSegments: project.edit.speedSegments
            )

            let renderer = try MetalRenderer()
            renderer.renderConfiguration = RenderConfiguration.fromProjectBackground(project.edit.background)

            let sourceVideoURL = packageURL.appendingPathComponent(project.assets.screen.path)
            let systemAudioURL = project.assets.systemAudio.map { packageURL.appendingPathComponent($0.path) }
            let micAudioURL = project.assets.mic.map { packageURL.appendingPathComponent($0.path) }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let request = ExportRequest(
                sourceVideoURL: sourceVideoURL,
                systemAudioURL: systemAudioURL,
                microphoneAudioURL: micAudioURL,
                timeMapping: mapping,
                outputURL: outputURL,
                preset: preset,
                renderer: renderer,
                temporaryDirectory: tempDir
            )

            let engine = ExportEngine()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await engine.export(request)
                    semaphore.signal()
                } catch {
                    print("Export failed: \(error)")
                    semaphore.signal()
                }
            }
            semaphore.wait()
            try? FileManager.default.removeItem(at: tempDir)
            print("Export complete: \(outputURL.path)")
        } catch {
            print("Export failed: \(error)")
            exit(1)
        }
    }

    private static func runPresets(_ args: [String]) {
        guard let packagePath = args.first else {
            print("presets requires a package path")
            return
        }
        let packageURL = URL(fileURLWithPath: packagePath)
        let projectURL = packageURL.appendingPathComponent(ProjectModel.projectFilename)
        do {
            let data = try Data(contentsOf: projectURL)
            let project = try ProjectModel.decodeJSON(data)
            for preset in project.edit.exportPresets {
                print("\(preset.name): \(preset.width)x\(preset.height) @ \(preset.fps)fps")
            }
        } catch {
            print("Failed to read presets: \(error)")
            exit(1)
        }
    }

    private static func printUsage() {
        print(
            """
            SmoothScreenCap CLI

            Commands:
              validate <package>                 Validate a project package
              package --output <pkg> --screen <file> [--events <file>] [--mic <file>] [--system <file>] [--webcam <file>]
                                               Create a project package from assets
              export <package> --preset <name> --output <file>
                                               Export a project using a named preset
              presets <package>                 List export presets in a project

            Flags:
              --app-version <version>            Set app version for package
              --no-auto-zoom                     Disable auto-zoom generation
            """
        )
    }
}

private struct ParsedArgs {
    let options: [String: String]
    let flags: Set<String>
    let positionals: [String]

    init(args: [String]) {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    options[key] = args[index + 1]
                    index += 2
                } else {
                    flags.insert(key)
                    index += 1
                }
            } else {
                positionals.append(arg)
                index += 1
            }
        }
        self.options = options
        self.flags = flags
        self.positionals = positionals
    }
}
