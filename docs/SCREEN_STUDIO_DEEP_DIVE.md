# Screen Studio deep dive (publicly observable)

Purpose
- Capture observable product behaviors and published stack details.
- Separate confirmed statements from inferences to avoid treating guesses as facts.

Evidence labels
- CONFIRMED: Explicitly described in public guides or engineering posts.
- INFERRED: Reasoned from product behavior or confirmed facts.

Product philosophy and editor model
- CONFIRMED: The app is an opinionated screen recorder + editor focused on demos, not a general-purpose NLE.
- CONFIRMED: Editor centers on a clip timeline plus a dedicated zoom timeline with zoom blocks.
- CONFIRMED: The editor exposes background framing controls (padding, rounded corners, shadows, background types).
- INFERRED: The editor is best understood as parameterized timelines layered on top of a base recording.

Zooms and camera work
- CONFIRMED: Zooms are first-class objects on a separate zoom timeline.
- CONFIRMED: Auto zooms are created from click positions; manual zooms can be placed and edited.
- CONFIRMED: Auto zoom creation can be disabled in settings.
- INFERRED: Zoom blocks map to a camera transform track applied at render time.

Cursor as an editable layer
- CONFIRMED: The UI exposes cursor visibility, size, cursor type, idle hiding, and smoothing toggles.
- CONFIRMED: Advanced cursor controls include rotation while moving, removing shakes, and cursor-type optimization.
- CONFIRMED: Cursor visibility can be toggled per fragment.
- INFERRED: Cursor behavior is treated as a renderable layer rather than only baked pixels.

Background framing and layout
- CONFIRMED: Background types include wallpaper, gradient, color, and image.
- CONFIRMED: Framing includes padding, rounded corners, inset, and shadow.
- INFERRED: The renderer composites the captured screen into a frame layout.

Motion and animation
- CONFIRMED: Motion blur options affect cursor, zoom in/out, and screen movement while zoomed.
- CONFIRMED: Animation styles expose presets and a "Newtonian" spring-like control (tension, friction, mass).
- INFERRED: A spring/damper model is used for camera and cursor motion.

Editing primitives beyond zooms
- CONFIRMED: Cut, trim, and speed changes are supported.
- CONFIRMED: Masks/highlights are supported but do not track scrolling.
- CONFIRMED: Typing detection is used to suggest speed-ups.
- INFERRED: Typing activity is captured or inferred as part of event logging.

Webcam layouts
- CONFIRMED: A separate layouts timeline is created when webcam layouts are enabled.

Captions
- CONFIRMED: Captions can be generated locally using Whisper (model size choices).
- CONFIRMED: Apple Speech Recognition can be used locally when available on supported macOS versions.

Export and sharing
- CONFIRMED: Export supports MP4 and GIF with FPS, size, and quality settings.
- CONFIRMED: Export time depends on FPS, resolution, and format; compression level does not change export time.
- CONFIRMED: Shareable links and a quick-share widget exist.

Project format and interchange
- CONFIRMED: Projects use a .screenstudio package and should be zipped when shared.
- CONFIRMED: Raw tracks (screen, mic, camera) can be extracted from projects.
- INFERRED: The project package contains media assets plus metadata.

Stack and architecture (publicly stated)
- CONFIRMED: Desktop app uses Electron for UI.
- CONFIRMED: A Swift command-line binary performs screen capture.
- CONFIRMED: Screen capture uses ScreenCaptureKit and AVAssetWriter.
- CONFIRMED: Export/render pipeline uses WebGL + WebCodecs with a deterministic export path.
- CONFIRMED: MP4 demuxing and GPU-backed decoding are used for fast deterministic export.
- CONFIRMED: ffmpeg is used for some audio/video operations.

Operational stack (partial)
- CONFIRMED: Privacy policy lists providers like Cloudflare, Vercel, Neon, PostHog, Sentry.
- INFERRED: A hosted backend supports shareable streaming links.

Key takeaways for SmoothScreenCap
- The UI feels like video editing, but the core is parameterized timelines over a base recording.
- Preview can drop frames; export is deterministic and frame-accurate.
- Rendering is GPU compositing with a separate cursor layer and camera transforms.
- Capture correctness (timebase, scale, codec limits) is critical to perceived polish.
