// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SmoothScreenCap",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ProjectModel", targets: ["ProjectModel"]),
    .library(name: "TimeMapping", targets: ["TimeMapping"]),
    .library(name: "AutoZoom", targets: ["AutoZoom"]),
    .library(name: "EventLog", targets: ["EventLog"]),
    .library(name: "ProjectPackaging", targets: ["ProjectPackaging"]),
    .library(name: "Recording", targets: ["Recording"]),
    .library(name: "Rendering", targets: ["Rendering"]),
    .library(name: "ExportEngine", targets: ["ExportEngine"]),
    .executable(name: "ssc-cli", targets: ["ssc-cli"]),
    .executable(name: "SmoothScreenCapApp", targets: ["SmoothScreenCapApp"])
  ],
  targets: [
    .executableTarget(
      name: "SmoothScreenCapApp",
      dependencies: [
        "ProjectModel",
        "TimeMapping",
        "AutoZoom",
        "EventLog",
        "ProjectPackaging",
        "ExportEngine",
        "Rendering",
        "Recording",
        "CursorSmoothing",
        "ClickSound"
      ],
      path: "App",
      resources: [.process("Resources")]
    ),
    .target(
      name: "CursorSmoothing",
      path: "Core/CursorSmoothing"
    ),
    .target(
      name: "ClickSound",
      path: "Core/ClickSound",
      resources: [.process("Resources")]
    ),
    .target(
      name: "ProjectModel",
      path: "Core/ProjectModel"
    ),
    .target(
      name: "TimeMapping",
      dependencies: ["ProjectModel"],
      path: "Core/TimeMapping"
    ),
    .target(
      name: "AutoZoom",
      dependencies: ["ProjectModel"],
      path: "Core/AutoZoom"
    ),
    .target(
      name: "EventLog",
      path: "Core/EventLog"
    ),
    .target(
      name: "ProjectPackaging",
      dependencies: ["ProjectModel", "AutoZoom", "EventLog"],
      path: "Core/ProjectPackaging"
    ),
    .target(
      name: "Recording",
      dependencies: ["EventLog"],
      path: "Recording"
    ),
    .target(
      name: "Rendering",
      dependencies: ["ProjectModel"],
      path: "Rendering",
      resources: [.process("Shaders")]
    ),
    .target(
      name: "ExportEngine",
      dependencies: ["ProjectModel", "TimeMapping", "Rendering", "EventLog"],
      path: "Export"
    ),
    .executableTarget(
      name: "ssc-cli",
      dependencies: [
        "ProjectModel",
        "TimeMapping",
        "AutoZoom",
        "EventLog",
        "ProjectPackaging",
        "ExportEngine",
        "Rendering"
      ],
      path: "Tools/ssc-cli"
    ),
    .testTarget(
      name: "ProjectModelTests",
      dependencies: ["ProjectModel"],
      path: "Tests/ProjectModelTests"
    ),
    .testTarget(
      name: "TimeMappingTests",
      dependencies: ["TimeMapping"],
      path: "Tests/TimeMappingTests"
    ),
    .testTarget(
      name: "AutoZoomTests",
      dependencies: ["AutoZoom"],
      path: "Tests/AutoZoomTests"
    ),
    .testTarget(
      name: "EventLogTests",
      dependencies: ["EventLog"],
      path: "Tests/EventLogTests"
    ),
    .testTarget(
      name: "ExportEngineTests",
      dependencies: ["ExportEngine", "ProjectModel", "Rendering", "TimeMapping"],
      path: "Tests/ExportEngineTests"
    ),
    .testTarget(
      name: "ProjectPackagingTests",
      dependencies: ["ProjectPackaging", "ProjectModel", "EventLog", "AutoZoom"],
      path: "Tests/ProjectPackagingTests"
    ),
    .testTarget(
      name: "RenderingTests",
      dependencies: ["Rendering"],
      path: "Tests/RenderingTests"
    )
  ]
)
