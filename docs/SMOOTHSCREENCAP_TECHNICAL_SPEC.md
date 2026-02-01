# SmoothScreenCap technical spec

Version
- Date: 2026-01-30
- Status: Draft

High-level architecture
- Swift + SwiftUI app shell (recording UI, editor UI, library).
- ScreenCaptureKit for screen and system audio capture.
- AVFoundation for asset IO and muxing.
- Metal for real-time compositing.
- VideoToolbox (via AVAssetWriter or VTCompressionSession) for encoding.
- Optional (V1): whisper.cpp (Metal) or Apple Speech for local captions.

Component diagram

SwiftUI App
  - Recording UI / Editor UI
  - Project management
    | 
    +--> Recorder (ScreenCaptureKit + AVFoundation)
    |
    +--> Editor Core (timelines and time mapping)
    |
    +--> Render Engine (Metal)
          - Background/frame
          - Camera transforms
          - Cursor overlay
          - Optional overlays
                |
                +--> Preview (drop frames OK)
                +--> Export Engine (deterministic)

Recording pipeline

Screen and system audio capture
- Configure SCStream for display / window / region.
- Capture at pixel resolution (not points).
- Exclude system cursor by default.
- Handle multiple audio outputs for system audio, filter by selected apps.

Writing to disk
- Use AVAssetWriter for video (H.264 default; HEVC optional).
- Store audio in separate .m4a tracks (mic and system).

Capture edge cases to handle
- Retina scale factor must be respected.
- Codec resolution limits (H.264 max around 4K-ish); downscale 5K/6K safely.
- Retime sample buffers to start at zero to avoid missing first frames.
- If the screen is static and produces few frames, repeat last frame to match duration.

Mic capture
- AVAudioEngine or AVCaptureSession audio input.
- Record to mic.m4a with timestamps aligned to recording timebase.

Webcam capture (optional)
- AVCaptureSession -> webcam.mov.
- Store device format and frame rate in metadata.

Event logging
- High-resolution event stream with timebase aligned to recording.
- Mouse events: position (global and captured), button down/up, scroll.
- Keyboard events: keyDown only, without key values by default.
- Use CGEventTapCreate (no fallback).
- Store as JSON Lines in events.jsonl.

Project model

Concept
- Parametric editing: timelines and parameters over a base recording.
- Two time domains: source time and output time.

Core objects
- Project
  - id, createdAt, version
  - assets: screen, mic, systemAudio, webcam, events
  - edit:
    - cuts[]
    - speedSegments[]
    - zoomSegments[]
    - cursorOverrides[]
    - background settings
    - motion settings
    - export presets

Time mapping
- TimeMapper supports:
  - sourceTime -> outputTime
  - outputTime -> sourceTime
- Handles cuts and speed changes with discontinuities.
- Used by scrubber, preview, and export.

Auto-zoom algorithm
- Inputs: click events, output aspect ratio, padding, default zoom.
- Steps:
  1) Create intervals around clicks (pre-roll and post-roll).
  2) Merge overlapping intervals.
  3) Choose focus point (last click or weighted average).
  4) Compute target crop rect and clamp to bounds.
  5) Add settle time to prevent jitter.

Cursor smoothing and rendering
- Resample cursor positions at output frame times.
- Apply one smoothing option (default): One Euro filter.
- Remove micro-shakes with a small movement threshold.
- Hide cursor when idle for N ms.
- Optional rotation based on velocity direction.

Rendering engine (Metal)

Frame composition order
1) Background quad (color / gradient / image).
2) Screen video quad with camera transform, rounded-rect clip, shadow.
3) Cursor overlay (sprite).
4) Optional overlays (highlight, blur mask, captions, webcam).

Motion blur
- MVP: cursor-only blur or none.
- V1: multi-sample blur for camera movement (optional, expensive).

Preview vs export
- Preview: real-time, frame drops allowed.
- Export: deterministic, frame-accurate iteration.

Export engine

Video
- For each output frame i:
  - time = i / fps
  - sourceTime = TimeMapper.outputToSource(time)
  - Decode source frame (AVAssetReader) -> CVPixelBuffer
  - Render composite in Metal -> CVPixelBuffer
  - Append to AVAssetWriterInputPixelBufferAdaptor

Audio
- Build AVMutableComposition for mic and system audio.
- Apply time scaling per segment with pitch preservation.
- Export to AAC, then mux with video.
- Optional FFmpeg module if AVFoundation has limitations (keep optional).

Determinism
- Fixed seeds for any randomness.
- Stable float math in shaders.
- Store engine version in project metadata.
- Warn when opening older project versions.

Testing strategy
- Golden frame tests
  - Fixture project with known output frames.
  - Compare pixel hashes with tolerance.
- AV sync tests
  - Metronome tick + click marker.
  - Drift below threshold after cuts/speed changes.
- TimeMapper tests
  - Invertibility checks and boundary tests.
- Performance benchmarks
  - Export throughput and memory ceilings.

Suggested repo layout
SmoothScreenCap/
  App/
  Core/
    ProjectModel/
    TimeMapping/
    AutoZoom/
    EventLog/
  Recording/
    ScreenCaptureKitBackend/
    AudioCapture/
    WebcamCapture/
  Rendering/
    MetalRenderer/
    Shaders/
  Export/
    ExportEngine/
    AudioEngine/
  Tools/
    ssc-cli/
  Docs/

Privacy and security
- No telemetry by default.
- Projects saved locally only.
- Optional build flag for crash reporting.
- Event logs store typing activity only, not keystrokes.
- Privacy mode toggle to disable event logging entirely.
