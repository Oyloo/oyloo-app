# OylooDesktop Audio Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that records mic (left channel) and system audio (right channel) simultaneously as a stereo M4A file, with click/hotkey start-stop and optional VAD auto-recording.

**Architecture:** New `OylooDesktop` Xcode target (macOS 14+) alongside the existing iOS target in `oyloo-app`. `RecordingEngine` owns one `AVAudioEngine`: mic routes through a panned mixer node (left), system audio from ScreenCaptureKit feeds an `AVAudioPlayerNode` through a second panned mixer (right). A tap on `mainMixerNode` writes stereo M4A via `AVAudioFile`. `VADDetector` monitors a secondary tap on the mic mixer. `HotkeyManager` registers a `CGEventTap` for ⌥⇧R.

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation, ScreenCaptureKit, CoreGraphics (CGEventTap), XCTest, xcodegen 2.45.4

---

## File Map

| File | Role |
|---|---|
| `project.yml` | Add OylooDesktop + OylooDesktopTests targets |
| `Sources/OylooDesktop/Info.plist` | LSUIElement, NSMicrophoneUsageDescription |
| `Sources/OylooDesktop/OylooDesktop.entitlements` | Microphone entitlement |
| `Sources/OylooDesktop/RecorderApp.swift` | `@main`, MenuBarExtra, HotkeyManager wiring |
| `Sources/OylooDesktop/VADDetector.swift` | Pure RMS computation, voice threshold |
| `Sources/OylooDesktop/StereoWriter.swift` | Filename generation, AVAudioFile M4A writing |
| `Sources/OylooDesktop/SystemCapture.swift` | ScreenCaptureKit → AVAudioPCMBuffer |
| `Sources/OylooDesktop/RecordingEngine.swift` | @Observable coordinator, AVAudioEngine graph |
| `Sources/OylooDesktop/HotkeyManager.swift` | CGEventTap, ⌥⇧R → toggle callback |
| `Sources/OylooDesktop/MenuBarView.swift` | SwiftUI popover UI |
| `Tests/OylooDesktopTests/VADDetectorTests.swift` | RMS and threshold tests |
| `Tests/OylooDesktopTests/StereoWriterTests.swift` | Filename format tests |

---

### Task 1: Xcode target setup

**Files:**
- Modify: `project.yml`
- Create: `Sources/OylooDesktop/Info.plist`
- Create: `Sources/OylooDesktop/OylooDesktop.entitlements`
- Create: `Sources/OylooDesktop/RecorderApp.swift` (stub)
- Create: `Tests/OylooDesktopTests/PlaceholderTests.swift`

- [ ] **Step 1: Add OylooDesktop and OylooDesktopTests to project.yml**

Open `project.yml` and append to the `targets:` key:

```yaml
  OylooDesktop:
    type: application
    platform: macOS
    sources:
      - Sources/OylooDesktop
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.oyloo.desktop
        INFOPLIST_FILE: Sources/OylooDesktop/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/OylooDesktop/OylooDesktop.entitlements
        PRODUCT_NAME: OylooDesktop
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.10"
        IPHONEOS_DEPLOYMENT_TARGET: ""

  OylooDesktopTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/OylooDesktopTests
    dependencies:
      - target: OylooDesktop
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.oyloo.desktop.tests
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.10"
        IPHONEOS_DEPLOYMENT_TARGET: ""
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/OylooDesktop.app/Contents/MacOS/OylooDesktop"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 2: Create Sources/OylooDesktop/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OylooDesktop</string>
    <key>CFBundleIdentifier</key>
    <string>com.oyloo.desktop</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>OylooDesktop records your microphone to capture conversations.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 3: Create Sources/OylooDesktop/OylooDesktop.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create Sources/OylooDesktop/RecorderApp.swift (stub)**

```swift
import SwiftUI

@main
struct RecorderApp: App {
    var body: some Scene {
        MenuBarExtra("OylooDesktop", systemImage: "waveform") {
            Text("Loading…").padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Create Tests/OylooDesktopTests/ and placeholder**

```bash
mkdir -p /Users/oyloo/dev/oyloo/oyloo-app/Tests/OylooDesktopTests
```

Create `Tests/OylooDesktopTests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }
}
```

- [ ] **Step 6: Regenerate Xcode project**

```bash
cd /Users/oyloo/dev/oyloo/oyloo-app && xcodegen generate
```

Expected output ends with: `✅ Done`

- [ ] **Step 7: Build OylooDesktop**

```bash
xcodebuild -project LifeOSShare.xcodeproj -scheme OylooDesktop \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add project.yml Sources/OylooDesktop/ Tests/OylooDesktopTests/
git commit -m "feat(desktop): add OylooDesktop macOS target skeleton"
```

---

### Task 2: VADDetector

**Files:**
- Create: `Sources/OylooDesktop/VADDetector.swift`
- Create: `Tests/OylooDesktopTests/VADDetectorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/OylooDesktopTests/VADDetectorTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import OylooDesktop

final class VADDetectorTests: XCTestCase {
    let vad = VADDetector()

    private func buffer(frames: Int, amplitude: Float) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 44100, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        let ch = buf.floatChannelData![0]
        for i in 0..<frames { ch[i] = amplitude }
        return buf
    }

    func testSilenceIsNotVoice() {
        XCTAssertFalse(vad.isVoiceActive(in: buffer(frames: 1024, amplitude: 0.0)))
    }

    func testMinus20dBFSIsVoice() {
        // -20 dBFS is above the -40 dBFS threshold
        let amp = pow(10.0 as Float, -20.0 / 20.0)
        XCTAssertTrue(vad.isVoiceActive(in: buffer(frames: 1024, amplitude: amp)))
    }

    func testMinus41dBFSIsNotVoice() {
        // -41 dBFS is just below the -40 dBFS threshold
        let amp = pow(10.0 as Float, -41.0 / 20.0)
        XCTAssertFalse(vad.isVoiceActive(in: buffer(frames: 1024, amplitude: amp)))
    }

    func testRMSOfConstantSignal() {
        // RMS of a constant 0.5 signal should be 0.5
        let rms = vad.rms(of: buffer(frames: 512, amplitude: 0.5))
        XCTAssertEqual(rms, 0.5, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project LifeOSShare.xcodeproj -scheme OylooDesktopTests \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAILED — `VADDetector` not defined.

- [ ] **Step 3: Create Sources/OylooDesktop/VADDetector.swift**

```swift
import AVFoundation

struct VADDetector {
    let thresholdDBFS: Float = -40.0
    let holdTime: TimeInterval = 2.0
    let minDuration: TimeInterval = 1.0

    private var threshold: Float { pow(10.0, thresholdDBFS / 20.0) }

    func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }
        var sumSquares: Float = 0
        for c in 0..<channelCount {
            for i in 0..<frameCount {
                let s = data[c][i]
                sumSquares += s * s
            }
        }
        return sqrt(sumSquares / Float(frameCount * channelCount))
    }

    func isVoiceActive(in buffer: AVAudioPCMBuffer) -> Bool {
        rms(of: buffer) >= threshold
    }
}
```

- [ ] **Step 4: Run tests — verify all pass**

```bash
xcodebuild test -project LifeOSShare.xcodeproj -scheme OylooDesktopTests \
  -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: 4 tests pass. `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/OylooDesktop/VADDetector.swift Tests/OylooDesktopTests/VADDetectorTests.swift
git commit -m "feat(desktop): add VADDetector with RMS voice activity detection"
```

---

### Task 3: StereoWriter

**Files:**
- Create: `Sources/OylooDesktop/StereoWriter.swift`
- Create: `Tests/OylooDesktopTests/StereoWriterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/OylooDesktopTests/StereoWriterTests.swift`:

```swift
import XCTest
@testable import OylooDesktop

final class StereoWriterTests: XCTestCase {
    func testFilenameFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 29
        comps.hour = 14; comps.minute = 23
        let date = cal.date(from: comps)!
        let url = StereoWriter.makeOutputURL(date: date, baseDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(url.lastPathComponent, "260429-1423-recording.m4a")
    }

    func testOutputIsInsideBaseDirectory() {
        let base = URL(fileURLWithPath: "/tmp/oyloo-test")
        let url = StereoWriter.makeOutputURL(date: Date(), baseDirectory: base)
        XCTAssertTrue(url.path.hasPrefix(base.path))
    }

    func testFileExtensionIsM4A() {
        let url = StereoWriter.makeOutputURL(date: Date(), baseDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(url.pathExtension, "m4a")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project LifeOSShare.xcodeproj -scheme OylooDesktopTests \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAILED — `StereoWriter` not defined.

- [ ] **Step 3: Create Sources/OylooDesktop/StereoWriter.swift**

```swift
import AVFoundation

final class StereoWriter {
    private var file: AVAudioFile?

    static func makeOutputURL(date: Date = Date(), baseDirectory: URL = defaultDirectory) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMdd-HHmm"
        fmt.timeZone = TimeZone.current
        let name = "\(fmt.string(from: date))-recording.m4a"
        return baseDirectory.appendingPathComponent(name)
    }

    static var defaultDirectory: URL {
        URL.homeDirectory.appendingPathComponent("Downloads/Recordings", isDirectory: true)
    }

    private(set) var outputURL: URL?

    func start(outputURL: URL, stereoSampleRate: Double) throws {
        self.outputURL = outputURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: stereoSampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        file = try AVAudioFile(forWriting: outputURL, settings: settings)
    }

    func write(buffer: AVAudioPCMBuffer) {
        try? file?.write(from: buffer)
    }

    func stop() {
        file = nil  // closes and flushes the file
        outputURL = nil
    }

    // Closes the file and deletes it (used when VAD segment is too short).
    func discard() {
        let url = outputURL
        file = nil
        outputURL = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
```

- [ ] **Step 4: Run all tests — verify they pass**

```bash
xcodebuild test -project LifeOSShare.xcodeproj -scheme OylooDesktopTests \
  -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: 7 tests pass (4 VAD + 3 StereoWriter). `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/OylooDesktop/StereoWriter.swift Tests/OylooDesktopTests/StereoWriterTests.swift
git commit -m "feat(desktop): add StereoWriter with AVAudioFile M4A output and filename logic"
```

---

### Task 4: SystemCapture

**Files:**
- Create: `Sources/OylooDesktop/SystemCapture.swift`

- [ ] **Step 1: Create Sources/OylooDesktop/SystemCapture.swift**

```swift
import ScreenCaptureKit
import AVFoundation
import CoreMedia

final class SystemCapture: NSObject {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var stream: SCStream?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 44100
        config.channelCount = 1

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    enum CaptureError: Error {
        case noDisplay
    }
}

extension SystemCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              let pcm = sampleBuffer.toFloat32MonoPCMBuffer() else { return }
        onBuffer?(pcm)
    }
}

private extension CMSampleBuffer {
    func toFloat32MonoPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)!.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0,
            frameCount: Int32(frameCount),
            into: sourceBuffer.mutableAudioBufferList
        ) == noErr else { return nil }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100, channels: 1, interleaved: false
        )!
        if sourceFormat == targetFormat { return sourceBuffer }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let targetBuffer = AVAudioPCMBuffer(
                  pcmFormat: targetFormat,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return nil }

        var error: NSError?
        converter.convert(to: targetBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        return error == nil ? targetBuffer : nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project LifeOSShare.xcodeproj -scheme OylooDesktop \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/OylooDesktop/SystemCapture.swift
git commit -m "feat(desktop): add SystemCapture via ScreenCaptureKit"
```

---

### Task 5: RecordingEngine

**Files:**
- Create: `Sources/OylooDesktop/RecordingEngine.swift`

The engine graph uses a single `AVAudioEngine`:
- `engine.inputNode` → `micMixer` (pan -1.0, full left) → `mainMixerNode`
- `playerNode` (system audio) → `sysMixer` (pan +1.0, full right) → `mainMixerNode`
- A VAD tap on `micMixer` monitors voice level
- A write tap on `mainMixerNode` records stereo output when recording

- [ ] **Step 1: Create Sources/OylooDesktop/RecordingEngine.swift**

```swift
import AVFoundation
import Observation

enum RecordingState: Equatable {
    case idle
    case recording
    case vadListening
}

@Observable
final class RecordingEngine {
    var state: RecordingState = .idle
    var duration: TimeInterval = 0
    var vadEnabled: Bool = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let micMixer = AVAudioMixerNode()
    private let sysMixer = AVAudioMixerNode()
    private let writer = StereoWriter()
    private let vad = VADDetector()
    private var systemCapture: SystemCapture?
    private var graphConfigured = false
    private var durationTimer: Timer?
    private var vadSilenceStart: Date?
    private var vadStarting = false
    private var recordingStartDate: Date?

    var isRecording: Bool { state == .recording }

    // MARK: - Public

    func toggleRecording() {
        switch state {
        case .idle, .vadListening:
            Task { try? await startRecording() }
        case .recording:
            stopRecording()
        }
    }

    func startRecording() async throws {
        guard state != .recording else { return }
        if !engine.isRunning {
            try await startEngine()
        }
        let url = StereoWriter.makeOutputURL()
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        try writer.start(outputURL: url, stereoSampleRate: format.sampleRate)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buf, _ in
            self?.writer.write(buffer: buf)
            self?.handleOutputBuffer(buf)
        }
        recordingStartDate = Date()
        DispatchQueue.main.async { [weak self] in
            self?.state = .recording
            self?.startTimer()
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        writer.stop()
        recordingStartDate = nil
        stopTimer()
        duration = 0
        if vadEnabled {
            state = .vadListening
        } else {
            state = .idle
            stopEngine()
        }
    }

    private func discardRecording() {
        guard state == .recording else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        writer.discard()
        recordingStartDate = nil
        stopTimer()
        duration = 0
        state = .vadListening
    }

    func setVAD(enabled: Bool) {
        vadEnabled = enabled
        switch (state, enabled) {
        case (.idle, true):
            state = .vadListening
            Task { try? await startEngine() }
        case (.vadListening, false):
            state = .idle
            stopEngine()
        default:
            break
        }
    }

    // MARK: - Engine lifecycle

    private func startEngine() async throws {
        configureGraphOnce()
        if systemCapture == nil {
            let capture = SystemCapture()
            capture.onBuffer = { [weak self] buf in
                guard let self, self.engine.isRunning else { return }
                self.playerNode.scheduleBuffer(buf)
            }
            try await capture.start()
            systemCapture = capture
        }
        try engine.start()
        playerNode.play()
    }

    private func stopEngine() {
        engine.stop()
        Task {
            await systemCapture?.stop()
            systemCapture = nil
        }
    }

    private func configureGraphOnce() {
        guard !graphConfigured else { return }
        graphConfigured = true

        engine.attach(playerNode)
        engine.attach(micMixer)
        engine.attach(sysMixer)

        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: micMixer, format: inputFmt)
        micMixer.pan = -1.0

        let sysFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 44100, channels: 1, interleaved: false)!
        engine.connect(playerNode, to: sysMixer, format: sysFmt)
        sysMixer.pan = 1.0

        let stereoFmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(micMixer, to: engine.mainMixerNode, format: stereoFmt)
        engine.connect(sysMixer, to: engine.mainMixerNode, format: stereoFmt)

        // VAD monitoring tap on micMixer (runs whenever engine is running)
        micMixer.installTap(onBus: 0, bufferSize: 1024, format: stereoFmt) { [weak self] buf, _ in
            self?.handleVADStart(buf)
        }
    }

    // MARK: - VAD

    private func handleVADStart(_ buffer: AVAudioPCMBuffer) {
        guard vadEnabled, state == .vadListening, !vadStarting else { return }
        guard vad.isVoiceActive(in: buffer) else { return }
        vadStarting = true
        Task { @MainActor in
            try? await self.startRecording()
            self.vadStarting = false
        }
    }

    private func handleOutputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard vadEnabled, state == .recording else { return }
        if vad.isVoiceActive(in: buffer) {
            vadSilenceStart = nil
        } else {
            if vadSilenceStart == nil { vadSilenceStart = Date() }
            if let silenceStart = vadSilenceStart,
               Date().timeIntervalSince(silenceStart) >= vad.holdTime {
                vadSilenceStart = nil
                let elapsed = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
                if elapsed < vad.minDuration {
                    // Too short — discard the file rather than saving it
                    DispatchQueue.main.async { [weak self] in self?.discardRecording() }
                } else {
                    DispatchQueue.main.async { [weak self] in self?.stopRecording() }
                }
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.duration += 1
        }
    }

    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project LifeOSShare.xcodeproj -scheme OylooDesktop \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/OylooDesktop/RecordingEngine.swift
git commit -m "feat(desktop): add RecordingEngine with AVAudioEngine stereo graph and VAD"
```

---

### Task 6: HotkeyManager

**Files:**
- Create: `Sources/OylooDesktop/HotkeyManager.swift`

- [ ] **Step 1: Create Sources/OylooDesktop/HotkeyManager.swift**

```swift
import AppKit

final class HotkeyManager {
    var onToggle: (() -> Void)?

    // ⌥⇧R: keyCode 15 (R), flags = .maskAlternate | .maskShift
    private let targetKeyCode = CGKeyCode(15)
    private let targetFlags: CGEventFlags = [.maskAlternate, .maskShift]
    private var eventTap: CFMachPort?

    func register() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        guard let tap = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .listenOnly,
            mask,
            { _, _, event, refcon -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                let keyCode = CGKeyCode(event!.getIntegerValueField(.keyboardEventKeycode))
                let flags = event!.flags.intersection([.maskAlternate, .maskShift, .maskCommand, .maskControl])
                if keyCode == manager.targetKeyCode && flags == manager.targetFlags {
                    DispatchQueue.main.async { manager.onToggle?() }
                }
                return Unmanaged.passRetained(event!)
            },
            selfPtr
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unregister() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project LifeOSShare.xcodeproj -scheme OylooDesktop \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/OylooDesktop/HotkeyManager.swift
git commit -m "feat(desktop): add HotkeyManager with CGEventTap for ⌥⇧R"
```

---

### Task 7: MenuBarView and final RecorderApp wiring

**Files:**
- Create: `Sources/OylooDesktop/MenuBarView.swift`
- Modify: `Sources/OylooDesktop/RecorderApp.swift`

- [ ] **Step 1: Create Sources/OylooDesktop/MenuBarView.swift**

```swift
import SwiftUI

struct MenuBarView: View {
    var engine: RecordingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            toggleButton.padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            vadToggleRow.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            openFolderButton.padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(width: 240)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isRecording ? Color.red : Color.secondary)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline)
            Spacer()
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: return "Idle"
        case .vadListening: return "Listening…"
        case .recording: return "Recording  \(formattedDuration)"
        }
    }

    private var formattedDuration: String {
        let h = Int(engine.duration) / 3600
        let m = Int(engine.duration) / 60 % 60
        let s = Int(engine.duration) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var toggleButton: some View {
        Button(engine.isRecording ? "Stop" : "Start Recording") {
            engine.toggleRecording()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vadToggleRow: some View {
        Toggle("Auto-detect voice", isOn: Binding(
            get: { engine.vadEnabled },
            set: { engine.setVAD(enabled: $0) }
        ))
    }

    private var openFolderButton: some View {
        Button("Open Recordings Folder") {
            let url = StereoWriter.defaultDirectory
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Replace Sources/OylooDesktop/RecorderApp.swift**

```swift
import SwiftUI

@main
struct RecorderApp: App {
    @State private var engine = RecordingEngine()
    private let hotkey = HotkeyManager()

    private var menuBarIcon: String {
        switch engine.state {
        case .idle: return "waveform"
        case .recording: return "waveform.badge.mic"
        case .vadListening: return "waveform.slash"
        }
    }

    var body: some Scene {
        MenuBarExtra("OylooDesktop", systemImage: menuBarIcon) {
            MenuBarView(engine: engine)
        }
        .menuBarExtraStyle(.window)
        .task {
            hotkey.onToggle = { engine.toggleRecording() }
            hotkey.register()
        }
    }
}
```

- [ ] **Step 3: Build final app**

```bash
xcodebuild -project LifeOSShare.xcodeproj -scheme OylooDesktop \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project LifeOSShare.xcodeproj -scheme OylooDesktopTests \
  -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: 7 tests pass. `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/OylooDesktop/MenuBarView.swift Sources/OylooDesktop/RecorderApp.swift
git commit -m "feat(desktop): add MenuBarView and wire full app - OylooDesktop v1 complete"
```

---

### Task 8: Smoke test on device

- [ ] **Step 1: Open in Xcode and run**

```bash
open /Users/oyloo/dev/oyloo/oyloo-app/LifeOSShare.xcodeproj
```

Select scheme **OylooDesktop**, destination **My Mac**, press ⌘R.

- [ ] **Step 2: Grant microphone permission**

When prompted, click OK. If not prompted, go to System Settings → Privacy & Security → Microphone and enable OylooDesktop.

- [ ] **Step 3: Grant Screen Recording permission**

System Settings → Privacy & Security → Screen Recording → enable OylooDesktop. Restart the app after granting.

- [ ] **Step 4: Test manual recording**

1. Click the `waveform` icon in the menu bar
2. Click **Start Recording** — icon changes to `waveform.badge.mic`
3. Play music or a YouTube video (populates the system audio track)
4. Speak a sentence into the mic
5. Wait 5 seconds, then click **Stop**
6. Click **Open Recordings Folder**
7. Verify `~/Downloads/Recordings/` contains a file named `yymmdd-hhmm-recording.m4a`
8. Open the file in QuickTime — verify it plays with ~5 s of audio

- [ ] **Step 5: Verify stereo channel separation**

Open the M4A in any DAW or audio editor (e.g., Audacity, Logic). Pan left/right. Verify:
- Left channel: microphone audio only
- Right channel: system audio only

- [ ] **Step 6: Test global hotkey**

1. Switch to Finder or any other app
2. Press ⌥⇧R — icon in menu bar changes to `waveform.badge.mic`
3. Press ⌥⇧R again — recording stops, new file saved

- [ ] **Step 7: Test VAD mode**

1. Enable **Auto-detect voice** toggle
2. Stay silent for 10 seconds — no recording should start
3. Speak aloud — recording starts automatically (icon changes)
4. Stop speaking — after 2 seconds of silence, recording stops and file is saved

- [ ] **Step 8: Final commit if smoke tests pass**

```bash
git add -p
git commit -m "chore(desktop): smoke tested OylooDesktop v1 on device"
```
