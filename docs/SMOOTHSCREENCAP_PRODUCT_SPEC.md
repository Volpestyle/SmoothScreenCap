# SmoothScreenCap product spec

Version
- Date: 2026-01-30
- Status: Draft

Vision
SmoothScreenCap is an open-source macOS screen recorder and demo editor that produces polished tutorials by default: automatic zooms, smooth cursor, clean framing, and fast export. It is opinionated (like Screen Studio), not a full NLE.

Goals
- Fast "record -> polish -> export" workflow.
- Offline-first, no account required.
- Transparent, hackable project format.
- Deterministic export suitable for tests.

Non-goals (MVP)
- Hosted share links or cloud player.
- Captions/transcripts.
- iOS/iPad capture.
- Advanced layout timelines (webcam, masks, captions).

Target users
- Indie founders shipping product updates on social.
- Developers recording quick demos and bug repros.
- Educators making tutorial content where cursor clarity matters.

Primary workflow (MVP)
1) Record screen (display/window/region) with mic and optional system audio.
2) Auto-zoom from clicks and smooth cursor by default.
3) Trim or cut a few segments.
4) Export MP4 (30/60 fps) or copy to clipboard.

MVP features and acceptance criteria

Recording
- Display / window / region capture
  - Accepts selection and starts capture within 2 seconds.
  - Captures at native pixel resolution with correct scale.
- Audio (mic + system)
  - Mic and system audio can be toggled independently.
  - Recorded audio is in sync with video on export.
- Optional webcam capture
  - If enabled, a separate webcam track is created and stored.
- Speaker notes window (lightweight)
  - Notes window can be shown/hidden without appearing in capture (when capturing a window or region).

Automatic polish
- Auto-zoom from clicks
  - Clicks generate zoom segments on the zoom timeline.
  - Users can disable auto-zoom before recording.
- Cursor smoothing
  - Smoothing is on by default and produces stable motion.
  - Smoothing can be disabled for a selected time range.
- Cursor size + idle hide
  - Cursor size is adjustable.
  - Cursor hides after a configurable idle duration.
- Click highlight + click sound
  - Click highlight is visible on left click.
  - Click sound can be toggled and has volume control.

Editor (simplified)
- Clip timeline
  - Trim in/out on the full recording.
  - Cut/remove arbitrary segments.
  - Segment speed changes (0.5x, 1x, 1.5x, 2x).
- Zoom timeline
  - View and edit auto-generated zoom blocks.
  - Convert a zoom block to manual and drag its target.
- Background framing
  - Color or gradient background.
  - Padding, rounded corners, and shadow controls.

Export
- MP4 export
  - Presets for 1080p/1440p/2160p and 30/60 fps.
  - Quality slider affects bitrate or target size.
  - Export completes deterministically (same input -> same output).
- Copy to clipboard
  - Exports to clipboard as MP4.

V1 features (post-MVP)
- Local captions and transcript editor.
- Masks/highlights (static, not tracking scroll).
- Background image/wallpaper library.
- Webcam layouts timeline (fullscreen/default/hidden).
- Speed-up typing segment suggestions.
- Presets system for look/feel profiles.
- GIF export.
- Project sharing as a single package file.

Information architecture

Top-level sections
1) New Recording
   - Source picker (display / window / region)
   - Audio toggles (mic / system audio with app selection)
   - Webcam toggle
   - Hide cursor in capture (recommended on)
   - Auto-zoom from clicks toggle
   - Hotkey config

2) Editor
   - Center preview
   - Right sidebar tabs: Background, Cursor, Zoom, Audio, Export
   - Timelines: Clip (yellow), Zoom (purple)
   - V1: Layouts / Masks / Captions

3) Library
   - Recent projects list
   - Reveal in Finder
   - Export last used preset

File format and openness
- Single package directory with:
  - project.json
  - screen video track
  - mic/system audio tracks
  - optional webcam track
  - events.jsonl
- Deterministic export with app version stored in metadata.

Licensing and branding
- Code: Apache-2.0 recommended (patent grant) or MIT.
- No Screen Studio branding or assets.
- "Inspired by" statement allowed without implying affiliation.

Success signals (MVP)
- A new user can go from record -> export in under 5 minutes.
- Exports are consistent across two runs of the same project.
- Cursor smoothing and auto-zoom are seen as clear improvements by testers.
