# OylooDesktop — Audio Recording Design

**Date:** 2026-04-29
**Scope:** macOS menu bar app, v1 (local recording only)
**Future phases:** server streaming, Watch control

---

## Summary

A standalone macOS menu bar app (`OylooDesktop`) that records microphone and system audio simultaneously as a stereo M4A file (mic = left channel, system = right channel). Start/stop via menu bar click or global hotkey. Optional VAD mode records automatically when voice is detected.

---

## Target

| Field | Value |
|---|---|
| Xcode target | `OylooDesktop` |
| Platform | macOS 14+ |
| Bundle ID | `com.oyloo.desktop` |
| `LSUIElement` | YES (menu bar only, no Dock icon) |

Added as a new target in `oyloo-app/project.yml` alongside the existing iOS target.

---

## Architecture

```
OylooDesktop/
├── RecorderApp.swift       — @main, MenuBarExtra scene
├── MenuBarView.swift       — popover UI
├── RecordingEngine.swift   — @Observable coordinator
├── MicCapture.swift        — AVAudioEngine mic tap
├── SystemCapture.swift     — ScreenCaptureKit system audio
├── StereoWriter.swift      — AVAssetWriter → stereo M4A
├── VADDetector.swift       — RMS amplitude threshold
└── HotkeyManager.swift     — CGEventTap global hotkey
```

Data flow:

```
MicCapture    ──┐
                ├──► RecordingEngine ──► StereoWriter ──► .m4a file
SystemCapture ──┘         │
                      VADDetector (when enabled)
```

`RecordingEngine` is the single stateful object (`@Observable`). All components receive start/stop from it and push PCM buffers to it. Designed with a sink interface so server streaming can be added later as a second sink without changing the pipeline.

---

## Audio Pipeline

### MicCapture
- `AVAudioEngine` with `inputNode`
- installTap: 1024 frames, 44.1 kHz mono PCM
- Pushes `AVAudioPCMBuffer` to `RecordingEngine`

### SystemCapture
- `SCStreamConfiguration` with `capturesAudio = true`
- 44.1 kHz, excludes current process audio: false
- Requires Screen Recording permission (prompted by ScreenCaptureKit on first use)
- Pushes `CMSampleBuffer` → converted to PCM → `RecordingEngine`

### StereoWriter
- `AVAssetWriter` + `AVAssetWriterInput`
- Format: `kAudioFormatMPEG4AAC`, 128 kbps, stereo
- Left channel = mic, right channel = system audio
- Buffers from both sources synchronized via presentation timestamps
- Output: `~/Downloads/Recordings/yymmdd-hhmm-recording.m4a`
  - Example: `260429-1423-recording.m4a`

---

## Menu Bar UI

Icon states:
- `waveform` — idle
- `waveform.badge.mic` (animated) — recording active
- `waveform.slash` — VAD mode, silence (paused)

Popover layout:
```
● Recording  00:03:42
────────────────────
  Stop              ⌥⇧R
────────────────────
  Auto-detect voice  [●]
────────────────────
  Open recordings folder
  Permissions…
  Quit
```

---

## Global Hotkey

- Default: `⌥⇧R`
- Implemented via `CGEventTap` (monitor mode — no Accessibility permission required)
- Managed by `HotkeyManager`, registered at app launch

---

## VAD (Voice Activity Detection)

`VADDetector` computes RMS of each mic buffer (1024 frames).

| Parameter | Value |
|---|---|
| Threshold | -40 dBFS |
| Hold time | 2.0 s (continue recording after silence) |
| Min duration | 1.0 s (discard segments shorter than this) |

Behaviour when VAD enabled:
- Voice detected → start new recording automatically
- Silence > holdTime → stop and save file
- Each active segment → separate M4A file
- Manual start/stop overrides VAD

---

## Permissions

| Permission | Trigger |
|---|---|
| Microphone | `NSMicrophoneUsageDescription` — prompted on first record |
| Screen Recording | ScreenCaptureKit prompts automatically on first system audio capture |

---

## Out of Scope (v1)

- Server streaming (WebSocket/HTTP) — architecture ready via sink interface
- Apple Watch control — future phase; Watch→iPhone→Mac path via WatchConnectivity + local network
- Speaker transcription — two separate tracks already identify speakers; `SFSpeechRecognizer` per track can be added as post-processing
- Configurable hotkey — hardcoded in v1
- Configurable output folder — hardcoded to `~/Downloads/Recordings/` in v1
