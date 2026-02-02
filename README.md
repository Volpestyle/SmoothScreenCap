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
│       ├── SettingsView.swift
│       ├── RegionSelector.swift
│       └── SpeakerNotesWindow.swift
├── Core/
│   ├── ProjectModel/       Project data model + JSON serialization
│   ├── TimeMapping/        Source ↔ output time conversion
│   ├── AutoZoom/           Click-based zoom generation
│   ├── EventLog/           Mouse/keyboard event capture (JSONL)
│   ├── CursorSmoothing/    One Euro filter for cursor jitter
│   ├── ClickSound/         Polyphonic click sound player
│   └── ProjectPackaging/   Project asset bundling
├── Recording/              ScreenCaptureKit + AVCaptureSession
├── Rendering/              Metal GPU compositor
├── Export/                 Video/audio composition engine
├── Tools/
│   └── ssc-cli/            Command-line interface
├── Tests/                  Unit tests (8 test suites)
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

**Core complete** — All major systems implemented and tested. Ready for UI polish and release.

### What's built

**Core Modules**
- **ProjectModel** — Full data model with JSON serialization, versioning, codec support
- **TimeMapping** — Bidirectional source ↔ output time conversion with cuts and speed segments
- **AutoZoom** — Click-based zoom generation with configurable focus modes and padding
- **EventLog** — Mouse, scroll, and keyboard event capture in JSONL format
- **CursorSmoothing** — One Euro filter implementation for jitter-free cursor motion
- **ClickSound** — Polyphonic click sound player with customizable sounds

**Recording**
- ScreenCaptureKit integration for screen capture
- Multi-track recording: screen video, system audio, microphone, webcam
- Real-time event logging via CGEvent tap
- Sample buffer timing synchronization

**Rendering**
- Metal GPU pipeline with 4 specialized shaders
- Background layer (solid colors, gradients, images)
- Screen layer with rounded corners, shadows, zoom cropping
- Cursor layer with texture rendering and hotspot positioning
- Click highlight ripple effect animation

**Export**
- Full video/audio composition and muxing
- Speed segment time-scaling with pitch preservation
- Click sound integration from event log
- H.264/HEVC codec support
- Deterministic output (same input = same output)

**App**
- SwiftUI app with Library, Recording, and Editor views
- Permission handling (screen recording, microphone)
- Project lifecycle and state management
- Dark theme pro-tool aesthetic

**Editor**
- 5-track timeline (Clip, Zoom, Speed, Cursor, Audio)
- Drag-to-resize for all segment types with snap-to-grid
- Context menus for segment actions (delete, reset, convert)
- CursorOverride track for per-segment cursor visibility/scale
- Numeric time input (TimeInput component) for precise editing
- Keyboard shortcuts (see below)
- ZoomTargetOverlay for visual zoom rect editing

**Editor Keyboard Shortcuts**

| Key | Action |
|-----|--------|
| `Space` | Play / Pause |
| `J` | Skip backward |
| `K` | Pause |
| `L` | Skip forward |
| `C` | Add cut at playhead |
| `Z` | Add zoom segment at playhead |
| `S` | Add speed segment at playhead |
| `Delete` / `Backspace` | Delete selected segment |
| `←` / `→` | Nudge selected segment by 1 frame |
| `Shift + ←` / `→` | Nudge selected segment by 10 frames |

**Testing**
- Comprehensive test suite covering all core modules
- Golden frame tests for rendering
- Deterministic hash validation for export

**CLI**
- `validate` — Validate project packages
- `package` — Create project packages
- `export` — Export videos
- `presets` — Show export presets

### What's next
- Webcam overlay positioning and compositing
- Background image support in UI
- Export progress UI and cancellation
- App distribution and signing

## License

Apache-2.0
