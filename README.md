# SmoothScreenCap

An open-source macOS screen recorder and demo editor that produces polished tutorials by default: automatic zooms, smooth cursor, clean framing, and fast export.

## Overview

SmoothScreenCap is an opinionated screen recording tool (inspired by Screen Studio) focused on producing polished demo videos with minimal effort. It's not a general-purpose video editor—it's a specialized tool for:

- **Indie founders** shipping product updates on social
- **Developers** recording quick demos and bug repros
- **Educators** making tutorial content where cursor clarity matters

### Key Features

- **Auto-zoom from clicks** — Automatically creates zoom segments when you click
- **Cursor smoothing** — One Euro filter removes micro-shakes for stable motion
- **Background framing** — Padding, rounded corners, shadows, color/gradient backgrounds
- **Clip timeline** — Trim, cut, and speed change segments
- **Zoom timeline** — View and edit auto-generated zoom blocks
- **Deterministic export** — Same input always produces same output (testable)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI App (Recording UI / Editor UI / Library)          │
├─────────────────────────────────────────────────────────────┤
│  Core Modules                                               │
│  ├─ ProjectModel    Data model + JSON serialization        │
│  ├─ TimeMapping     Source ↔ output time conversion        │
│  ├─ AutoZoom        Click-based zoom segment generation    │
│  └─ EventLog        Mouse/keyboard event capture           │
├─────────────────────────────────────────────────────────────┤
│  Recording          ScreenCaptureKit + AVFoundation        │
├─────────────────────────────────────────────────────────────┤
│  Rendering          Metal compositor (background, cursor)  │
├─────────────────────────────────────────────────────────────┤
│  Export             Deterministic frame-accurate export    │
└─────────────────────────────────────────────────────────────┘
```

## Quickstart

### Requirements

- macOS 14.0+
- Xcode 15+ (for development)
- Swift 5.9+

### Build and Run

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/SmoothScreenCap.git
cd SmoothScreenCap

# Build
swift build

# Run the app
swift run SmoothScreenCapApp
```

### Development

```bash
# Build all targets
swift build

# Run tests
swift test

# Build release
swift build -c release
```

### Project Structure

```
SmoothScreenCap/
├── App/                    SwiftUI application
│   ├── SmoothScreenCapApp.swift
│   ├── AppState.swift
│   ├── ContentView.swift
│   └── Views/
│       ├── LibraryView.swift
│       ├── RecordingView.swift
│       ├── EditorView.swift
│       └── SettingsView.swift
├── Core/
│   ├── ProjectModel/       Project data model
│   ├── TimeMapping/        Time domain conversion
│   ├── AutoZoom/           Zoom algorithm
│   └── EventLog/           Event capture
├── Recording/              ScreenCaptureKit backend
├── Rendering/              Metal renderer
├── Export/                 Export engine
├── Tools/
│   └── ssc-cli/            Command-line interface
├── Tests/                  Unit tests
└── docs/                   Documentation
    ├── SMOOTHSCREENCAP_PRODUCT_SPEC.md
    ├── SMOOTHSCREENCAP_TECHNICAL_SPEC.md
    ├── UI_ARCHITECTURE.md
    └── PROJECT_SCHEMA.json
```

## Documentation

- [Product Spec](docs/SMOOTHSCREENCAP_PRODUCT_SPEC.md) — Features, UX, acceptance criteria
- [Technical Spec](docs/SMOOTHSCREENCAP_TECHNICAL_SPEC.md) — Architecture, implementation details
- [UI Architecture](docs/UI_ARCHITECTURE.md) — SwiftUI patterns, components, conventions
- [Project Schema](docs/PROJECT_SCHEMA.json) — JSON schema for project files

## Status

**Early development** — UI scaffolding complete, core modules are stubs.

### What's built
- Full SwiftUI app with Library, Recording, and Editor views
- Navigation, state management, and component library
- Dark theme pro-tool aesthetic

### What's next
- Recording pipeline (ScreenCaptureKit integration)
- ProjectModel implementation matching JSON schema
- TimeMapper for source ↔ output time conversion
- Metal rendering pipeline
- Export engine

## License

Apache-2.0
