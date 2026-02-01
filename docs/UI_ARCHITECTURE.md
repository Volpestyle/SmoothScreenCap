# UI Architecture

This document describes the SwiftUI app architecture, patterns, and conventions used in SmoothScreenCap.

## Design Philosophy

The UI is a **pro-tool dashboard**, not a marketing site. Every screen should feel like a working tool with:
- Dense, information-rich layouts
- Monospace typography for labels and values
- Dark theme with subtle borders and minimal color
- No hero sections, promotional copy, or call-to-action patterns

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  SmoothScreenCapApp.swift                                   │
│  └─ @main entry point, WindowGroup + Settings scene        │
├─────────────────────────────────────────────────────────────┤
│  AppState.swift                                             │
│  └─ @MainActor ObservableObject, single source of truth    │
├─────────────────────────────────────────────────────────────┤
│  ContentView.swift                                          │
│  └─ HeaderBar + section router (Library/Recording/Editor)  │
├─────────────────────────────────────────────────────────────┤
│  Views/                                                     │
│  ├─ LibraryView.swift      Project grid + sidebar          │
│  ├─ RecordingView.swift    Source picker + settings        │
│  ├─ EditorView.swift       Preview + timeline + sidebar    │
│  └─ SettingsView.swift     App preferences (Settings scene)│
└─────────────────────────────────────────────────────────────┘
```

## State Management

### AppState (single ObservableObject)

All shared state lives in `AppState`. Views read from it via `@EnvironmentObject`.

```swift
@EnvironmentObject var appState: AppState
```

**State categories:**
- Navigation: `currentSection`, `selectedSidebarTab`
- Project: `currentProject`, `recentProjects`
- Recording: `isRecording`, `selectedSource`, `micEnabled`, etc.
- Playback: `isPlaying`, `currentTime`

**When to use AppState vs local @State:**
- `AppState`: Shared across views, persists during navigation, affects multiple components
- `@State`: Local UI state (hover, animation, form inputs before commit)

### Adding new state

1. Add the property to `AppState.swift`
2. If it needs persistence, use `@AppStorage` in `SettingsView.swift` and sync on launch

## Navigation

Three top-level sections controlled by `AppState.currentSection`:

```swift
enum AppSection: String, CaseIterable {
    case library = "Library"
    case recording = "Recording"
    case editor = "Editor"
}
```

Navigation happens via the `HeaderBar` nav buttons. To navigate programmatically:

```swift
appState.currentSection = .editor
```

## Layout Patterns

### Three-column layout (Recording, Editor)

```
┌──────────┬────────────────────────┬──────────┐
│  Left    │        Center          │  Right   │
│  Panel   │        Content         │  Panel   │
│  (280px) │       (flexible)       │  (280px) │
└──────────┴────────────────────────┴──────────┘
```

```swift
HStack(spacing: 0) {
    LeftPanel()
        .frame(width: 280)
        .background(Color(white: 0.06))

    CenterContent()
        .frame(maxWidth: .infinity)

    RightPanel()
        .frame(width: 280)
        .background(Color(white: 0.06))
}
```

### Sidebar section pattern

```swift
VStack(alignment: .leading, spacing: 0) {
    SidebarSectionHeader(title: "SECTION NAME")

    VStack(spacing: 12) {
        // Content rows
    }
    .padding(16)

    Divider()
        .background(Color.white.opacity(0.06))
}
```

### Panel backgrounds

- Main content area: `Color(white: 0.04)`
- Side panels: `Color(white: 0.06)`
- Elevated elements: `Color(white: 0.08)`
- Interactive hover: `Color.white.opacity(0.08)`

## Typography

All labels use system monospace for the tool aesthetic:

```swift
// Section headers
.font(.system(size: 10, weight: .semibold, design: .monospaced))
.foregroundStyle(.secondary)

// Values / metrics
.font(.system(size: 13, weight: .semibold, design: .monospaced))
.foregroundStyle(.white)

// Body text
.font(.system(size: 12))
.foregroundStyle(.secondary)

// Button labels
.font(.system(size: 11, weight: .semibold, design: .monospaced))
```

## Reusable Components

### SidebarSectionHeader
Header row for sidebar sections with uppercase label.

```swift
SidebarSectionHeader(title: "AUDIO")
```

### ToggleRow
Toggle with icon, title, and subtitle.

```swift
ToggleRow(
    icon: "mic.fill",
    title: "Microphone",
    subtitle: "MacBook Pro Microphone",
    isOn: $appState.micEnabled
)
```

### StatRow
Key-value display for stats.

```swift
StatRow(label: "TOTAL PROJECTS", value: "12")
```

### ShortcutRow
Keyboard shortcut with action label.

```swift
ShortcutRow(keys: "⌘ R", action: "Start recording")
```

### NavButton
Header navigation button with active state.

```swift
NavButton(title: "LIBRARY", isActive: true) {
    appState.currentSection = .library
}
```

## Adding a New Feature

### Example: Adding a new sidebar tab to the Editor

1. **Add the tab to the enum** in `AppState.swift`:
```swift
enum EditorSidebarTab: String, CaseIterable {
    // ...existing cases
    case captions = "Captions"

    var icon: String {
        switch self {
        // ...existing cases
        case .captions: return "captions.bubble"
        }
    }
}
```

2. **Create the tab content view** in `EditorView.swift`:
```swift
struct CaptionsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tab content
        }
        .padding(16)
    }
}
```

3. **Add to the switch** in `EditorSidebar`:
```swift
switch appState.selectedSidebarTab {
// ...existing cases
case .captions:
    CaptionsTab()
}
```

### Example: Adding a new timeline track

1. **Add track data** to `AppState` or the project model
2. **Add a TimelineTrack** in `TimelinePanel`:
```swift
TimelineTrack(
    label: "CAPS",
    color: .cyan,
    segments: captionSegments
)
```

## Color Palette

```swift
// Backgrounds (darkest to lightest)
Color.black                    // App background
Color(white: 0.04)            // Main content
Color(white: 0.06)            // Panels
Color(white: 0.08)            // Cards, elevated
Color.white.opacity(0.1)      // Hover, selected

// Borders
Color.white.opacity(0.06)     // Default
Color.white.opacity(0.15)     // Active/selected

// Text
.white                        // Primary
.secondary                    // Labels, muted
.tertiary                     // Hints, disabled

// Accent colors (timeline tracks)
.yellow                       // Clip track
.purple                       // Zoom track
.green                        // Audio track
.red                          // Recording indicator
.blue                         // Export/primary action
```

## Animation Conventions

Use subtle, quick animations:

```swift
// Navigation, state changes
withAnimation(.easeInOut(duration: 0.2)) { }

// Hover effects
.animation(.easeOut(duration: 0.15), value: isHovered)

// Continuous indicators (recording dot)
.animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBlinking)
```

## Testing Previews

Each view has a `#Preview` at the bottom. For views that need state:

```swift
#Preview {
    EditorView()
        .environmentObject({
            let state = AppState()
            state.currentProject = Project(name: "Test", duration: 120, createdAt: Date())
            return state
        }())
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
```

## File Organization

```
App/
├── SmoothScreenCapApp.swift   # @main entry point
├── AppState.swift             # Shared state
├── ContentView.swift          # Root view + header
└── Views/
    ├── LibraryView.swift      # Project browser
    ├── RecordingView.swift    # Capture setup
    ├── EditorView.swift       # Timeline editor (largest file)
    └── SettingsView.swift     # Preferences window
```

When a view file gets too large (>500 lines), extract sub-views into the same file or a dedicated file in `Views/`.

## Connecting to Core Modules

The UI imports core modules for data types and business logic:

```swift
import ProjectModel
import TimeMapping
import EventLog
import AutoZoom
```

UI should never contain business logic. Keep views as thin data bindings:
- **UI layer**: Display state, handle user input, call AppState methods
- **AppState**: Coordinate between UI and core modules
- **Core modules**: Business logic, data transformations, I/O
