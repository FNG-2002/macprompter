import XCTest
import AppKit
import AVFoundation
import Speech
import SwiftUI
@testable import MacPrompter

@MainActor
final class ReaderTests: XCTestCase {
    func testReaderScrollsAndHoverBlocksVoiceTarget() async throws {
        let store = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let session = PrompterSession(preferences: store)
        session.script = .welcome
        session.gate.isVisible = true
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        view.update(preferences: store.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(session.maximumOffset, 200)
        session.offset = 150
        view.update(preferences: store.value)
        view.layoutSubtreeIfNeeded()
        let clip = try XCTUnwrap(view.subviews.first as? NSClipView)
        XCTAssertEqual(clip.bounds.minY, 150, accuracy: 1)
        session.gate.isHovering = true
        session.targetCharacter = 400
        view.update(preferences: store.value)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(clip.bounds.minY, 150, accuracy: 1)
        session.setHover(false)
        XCTAssertNil(session.targetCharacter)
        session.nudge(80)
        view.update(preferences: store.value)
        XCTAssertEqual(clip.bounds.minY, 230, accuracy: 1)
        session.hide()
    }

    func testScrollingAndHighlightingReuseTextLayout() async throws {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.value.mode = .voice
        let session = PrompterSession(preferences: prefs)
        session.script = .welcome; session.reset()
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        view.update(preferences: prefs.value); view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let count = view.textLayoutCount
        let tokens = ScriptParser.words(in: session.script.body)
        for i in 0..<120 {
            session.offset = Double(i)
            session.activeWordRange = tokens[i % tokens.count].range
            view.update(preferences: prefs.value); view.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(view.textLayoutCount, count)
        let clip = try XCTUnwrap(view.subviews.first as? NSClipView)
        XCTAssertEqual(clip.bounds.minY, 119, accuracy: 0.1)
        XCTAssertFalse(view.needsLayout)
    }

    func testHeightOnlyResizeUpdatesScrollBoundsWithoutReflow() async throws {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let session = PrompterSession(preferences: prefs)
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        view.update(preferences: prefs.value); view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let originalMax = session.maximumOffset
        let count = view.textLayoutCount
        view.setFrameSize(NSSize(width: 500, height: 400))
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(view.textLayoutCount, count)
        XCTAssertEqual(session.maximumOffset, originalMax - 60, accuracy: 0.1)
        view.setFrameSize(NSSize(width: 350, height: 400))
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.textLayoutCount, count)
    }

    func testDisplayClockFollowsPlaybackHoverAndWindowAttachment() async throws {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.value.mode = .automatic
        let session = PrompterSession(preferences: prefs)
        session.gate.isVisible = true
        let host = NSHostingView(rootView: ReaderView(session: session, preferences: prefs.value))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 500, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { session.hide(); window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let reader = try XCTUnwrap(findReader(host))
        XCTAssertFalse(reader.isFrameClockRunning)
        session.gate.isPlaying = true
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(reader.isFrameClockRunning)
        XCTAssertGreaterThan(session.offset, 0)
        session.setHover(true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(reader.isFrameClockRunning)
        let frozen = session.offset
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.offset, frozen)
        session.setHover(false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(reader.isFrameClockRunning)
        XCTAssertGreaterThan(session.offset, frozen)
        window.contentView = nil
        XCTAssertFalse(reader.isFrameClockRunning)
    }

    func testHostedReaderUpdatesWordWithoutTimerDrivenViewRefresh() async throws {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.value.mode = .voice
        let session = PrompterSession(preferences: prefs)
        session.script = Script(title: "Test", body: "Hello brave world. Another sentence follows here.")
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        let host = NSHostingView(rootView: ReaderView(session: session, preferences: prefs.value))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        let reader = try XCTUnwrap(findReader(host))
        XCTAssertFalse(reader.isFrameClockRunning, "No window or frame clock is needed for a word update")
        session.receiveTranscript("Hello brave", segment: 0, endTime: 1)
        try await Task.sleep(for: .milliseconds(50))
        let clip = try XCTUnwrap(reader.subviews.first as? NSClipView)
        let text = try XCTUnwrap(clip.documentView as? NSTextView)
        let manager = try XCTUnwrap(text.layoutManager)
        XCTAssertEqual(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 6, effectiveRange: nil) as? NSColor, NSColor.white)
        session.receiveTranscript("Hello brave world", segment: 0, endTime: 2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 6, effectiveRange: nil))
        XCTAssertEqual(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 12, effectiveRange: nil) as? NSColor, NSColor.white)
        session.hide()
    }

    func testOverlayKeepsReaderWhenResizedAndRepositioned() async throws {
        let model = AppModel.shared
        let original = model.preferences.value
        let controller = OverlayController(model: model)
        defer { controller.hide(); model.preferences.value = original }
        controller.show()
        let panel = try XCTUnwrap(controller.panel)
        let host = try XCTUnwrap(panel.contentView)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        let first = try XCTUnwrap(findReader(host))
        model.preferences.value.width = original.width + 30
        model.preferences.value.height = original.height + 20
        controller.reposition()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(panel.contentView === host)
        XCTAssertTrue(findReader(host) === first)
        model.preferences.value.docked.toggle()
        controller.reposition()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(findReader(host) === first)
    }

    private func findReader(_ view: NSView) -> ReaderViewport? {
        if let reader = view as? ReaderViewport { return reader }
        return view.subviews.lazy.compactMap { self.findReader($0) }.first
    }

    func testBundledDyslexicFontAndCueContrast() throws {
        FontRegistration.register()
        let font = try XCTUnwrap(NSFont(name: "OpenDyslexic-Regular", size: 28))
        XCTAssertTrue(font.familyName?.contains("Dyslexic") == true)
        let styled = ScriptStyle.attributed("Hello [Pause] world", font: font, spacing: 12)
        let normal = try XCTUnwrap(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let cue = try XCTUnwrap(styled.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(normal, cue)
    }

    func testAudioConversionOwnsBuffersAndPreservesTimeline() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let converter = try MicrophoneConverter(from: inputFormat, to: target)
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 2048))
        source.frameLength = 2048
        for i in 0..<2048 { source.floatChannelData![0][i] = sin(Float(i) * 0.1) * 0.1 }
        let first = try converter.convert(source)
        let a = first
        let originalSample = a.buffer.int16ChannelData![0][100]
        for i in 0..<2048 { source.floatChannelData![0][i] = 0 }
        let second = try converter.convert(source)
        let b = second
        XCTAssertEqual(a.buffer.format.sampleRate, 16000)
        XCTAssertFalse(a.buffer === b.buffer)
        XCTAssertEqual(a.buffer.int16ChannelData![0][100], originalSample)
        XCTAssertGreaterThan(second.endTime, first.endTime)
        XCTAssertEqual(b.startTime.seconds, first.endTime, accuracy: 0.001)
    }

    func testSinkCaptureDeliversEverySampleInOrderOffTheAudioThread() throws {
        final class Collected: @unchecked Sendable {
            let lock = NSLock(); var samples: [Float] = []; var blocks: [Int] = []
        }
        let collected = Collected()
        let done = expectation(description: "all audio delivered")
        let total = 48 * 480
        let capture = try XCTUnwrap(AudioSinkCapture(sampleRate: 48000) { buffer in
            XCTAssertFalse(Thread.isMainThread)
            let data = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            collected.lock.lock()
            collected.samples += data; collected.blocks.append(data.count)
            let complete = collected.samples.count == total
            collected.lock.unlock()
            if complete { done.fulfill() }
        })
        DispatchQueue.global(qos: .userInteractive).async {
            var chunk = [Float](repeating: 0, count: 480)
            for block in 0..<48 {
                for i in 0..<480 { chunk[i] = Float(block * 480 + i) }
                chunk.withUnsafeBufferPointer { capture.write($0.baseAddress!, frames: 480) }
                usleep(2000)
            }
        }
        wait(for: [done], timeout: 5)
        capture.stop()
        collected.lock.lock(); defer { collected.lock.unlock() }
        XCTAssertEqual(collected.samples, (0..<total).map(Float.init))
        XCTAssertEqual(capture.dropped, 0)
        // Blocks follow the device callbacks, not the ~100 ms tap size.
        XCTAssertLessThanOrEqual(collected.blocks.max()!, 4 * 480)
    }

    func testSinkCaptureDropsAudioInsteadOfOverwritingUnreadSamples() throws {
        let capture = try XCTUnwrap(AudioSinkCapture(sampleRate: 1000, seconds: 0.001) { _ in })
        let samples = [Float](repeating: 1, count: 2000)
        samples.withUnsafeBufferPointer { capture.write($0.baseAddress!, frames: 2000) }
        XCTAssertEqual(capture.dropped, 2000)
        capture.stop()
    }

    func testSwitchedInputContinuesTheAnalyzerTimeline() throws {
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        func block(_ rate: Double) throws -> AVAudioPCMBuffer {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 100)))
            buffer.frameLength = buffer.frameCapacity
            return buffer
        }
        let builtIn = try MicrophoneConverter(from: try block(48000).format, to: target)
        var last = try builtIn.convert(try block(48000))
        for _ in 0..<9 { last = try builtIn.convert(try block(48000)) }
        // AirPods: a different hardware rate, same analyzer stream.
        let headset = try MicrophoneConverter(from: try block(24000).format, to: target, startingAt: builtIn.frames)
        let next = try headset.convert(try block(24000))
        XCTAssertEqual(next.startTime.seconds, last.endTime, accuracy: 0.002)
        XCTAssertGreaterThan(next.endTime, last.endTime)
    }

    func testMicrophoneTapCanRunOnAudioQueue() async throws {
        let sourceFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let targetFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let converter = try MicrophoneConverter(from: sourceFormat, to: targetFormat)
        let (stream, sink) = AsyncStream<AnalyzerInput>.makeStream()
        let delivered = expectation(description: "Audio queue delivered metrics")
        let tap = MicrophoneTap.make(converter: converter, sink: sink, onMetrics: { level, time in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertGreaterThan(time, 0)
            XCTAssertGreaterThanOrEqual(level, 0)
            delivered.fulfill()
        }, onFailure: { error in
            XCTFail(error.localizedDescription)
            delivered.fulfill()
        })
        DispatchQueue.global(qos: .userInitiated).async {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
            buffer.frameLength = 2048
            for i in 0..<2048 { buffer.floatChannelData![0][i] = 0.05 }
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: 48000))
            sink.finish()
        }
        await fulfillment(of: [delivered], timeout: 3)
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 1)
    }

    func testOverlayRendersAtNotchSize() throws {
        let model = AppModel.shared
        let view = NSHostingView(rootView: OverlayView(model: model, topInset: 32))
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 332)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1000)
        let url = FileManager.default.temporaryDirectory.appending(path: "macprompter-overlay.png")
        try data.write(to: url)
        print("OVERLAY_SNAPSHOT: \(url.path)")
    }
}

@MainActor
final class ScrollWheelTests: XCTestCase {
    private func makeSession(_ mode: PlaybackMode) -> PrompterSession {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.value.mode = mode
        let session = PrompterSession(preferences: prefs)
        session.script = .welcome; session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.maximumOffset = 1000
        return session
    }

    func testScrollWheelMovesEveryModeAndKeepsHoverPause() {
        for mode in PlaybackMode.allCases {
            let session = makeSession(mode)
            // macOS convention: a negative delta reveals later text.
            session.scrollWheel(deltaY: -40, precise: true)
            XCTAssertEqual(session.offset, 40, "\(mode)")
            session.setHover(true)
            session.nudge(80)
            XCTAssertEqual(session.offset, 40, "keys stay frozen during hover")
            session.scrollWheel(deltaY: -2, precise: false)
            XCTAssertEqual(session.offset, 40 + 2 * (28 + 12), "a wheel notch moves one line")
            XCTAssertTrue(session.gate.isHovering)
            XCTAssertTrue(session.gate.isPlaying)
            session.advanceReading(by: 0.5)
            XCTAssertEqual(session.offset, 120, "timer and voice stay frozen during hover")
            session.scrollWheel(deltaY: 500, precise: true)
            XCTAssertEqual(session.offset, 0)
            session.hide()
        }
    }

    func testCountdownAndHiddenPrompterIgnoreScrollWheel() {
        let session = makeSession(.manual)
        session.gate.countdown = 3
        session.scrollWheel(deltaY: -40, precise: true)
        XCTAssertEqual(session.offset, 0)
        session.gate.countdown = 0
        session.gate.isVisible = false
        session.scrollWheel(deltaY: -40, precise: true)
        XCTAssertEqual(session.offset, 0)
        var gate = PlaybackGate(isVisible: true, isPlaying: false, isHovering: true, countdown: 0)
        XCTAssertTrue(gate.allowsScrolling)
        XCTAssertFalse(gate.allowsMovement)
        gate.countdown = 1
        XCTAssertFalse(gate.allowsScrolling)
    }

    func testScrollingDuringHoverResyncsVoiceFollowing() async throws {
        let session = makeSession(.voice)
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        var moves = 0
        let synchronize = session.onManualMovement
        session.onManualMovement = { moves += 1; synchronize?() }
        session.setHover(true)
        session.scrollWheel(deltaY: -120, precise: true)
        XCTAssertEqual(moves, 1)
        XCTAssertNil(session.voiceDestination)
        XCTAssertNil(session.activeWordRange)
        session.hide()
    }

    func testLegacyPreferencesEnableScrollingAnywhere() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var prefs = Preferences(); prefs.mode = .manual; prefs.fontSize = 30
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        legacy["scrollAnywhere"] = nil
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "preferences.v1")
        let store = PreferenceStore(defaults: defaults)
        XCTAssertEqual(store.value.mode, .manual)
        XCTAssertEqual(store.value.fontSize, 30)
        XCTAssertTrue(store.value.scrollWheelAnywhere)
        store.value.scrollWheelAnywhere = false
        XCTAssertFalse(PreferenceStore(defaults: defaults).value.scrollWheelAnywhere)
    }

    func testPrompterPanelRoutesScrollEventsFromEveryArea() throws {
        let panel = PrompterPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var received: [Double] = []
        panel.onScrollWheel = { received.append($0.scrollingDeltaY) }
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0))
        panel.sendEvent(try XCTUnwrap(NSEvent(cgEvent: event)))
        XCTAssertEqual(received, [-40])
    }

    func testGlobalScrollMonitorOnlyWhileVisibleAndEnabled() {
        let model = AppModel.shared
        let original = model.preferences.value
        let overlay = OverlayController(model: model)
        var requests = 0
        model.listenAccess = { true }
        model.requestListenAccess = { requests += 1 }
        defer {
            overlay.hide(); model.preferences.value = original; model.session.setHover(false)
            model.listenAccess = { CGPreflightListenEventAccess() }; model.requestListenAccess = {}
        }
        model.preferences.value.scrollWheelAnywhere = true
        XCTAssertFalse(overlay.isMonitoringScrollWheel)
        overlay.show()
        XCTAssertTrue(overlay.isMonitoringScrollWheel)
        XCTAssertEqual(requests, 0, "no prompt once Input Monitoring is granted")
        model.preferences.value.scrollWheelAnywhere = false
        overlay.updateScrollMonitor()
        XCTAssertFalse(overlay.isMonitoringScrollWheel)
        model.preferences.value.scrollWheelAnywhere = true
        overlay.updateScrollMonitor()
        XCTAssertTrue(overlay.isMonitoringScrollWheel)
        overlay.hide()
        XCTAssertFalse(overlay.isMonitoringScrollWheel)
    }

    /// Regression: the old global monitor missed scrolling over areas that do
    /// not scroll and over the presentation windows.
    func testScrollTapCoversEverythingButPrompterAndAppWindows() {
        let rect = NSRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertTrue(OverlayController.tapHandlesScroll(over: nil), "other apps, desktop, non-scrolling areas")
        XCTAssertTrue(OverlayController.tapHandlesScroll(over: PresentationWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: true)))
        XCTAssertFalse(OverlayController.tapHandlesScroll(over: PrompterPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)), "the panel scrolls itself")
        XCTAssertFalse(OverlayController.tapHandlesScroll(over: NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)), "library and settings keep their scrolling")
    }

    /// Regression: on macOS 27 other apps' scroll events need Input Monitoring.
    func testMissingInputMonitoringIsRequestedAndShown() {
        let model = AppModel.shared
        XCTAssertTrue(AppModel.isTestHost, "other tests show the overlay and must not prompt")
        let original = model.preferences.value
        let overlay = OverlayController(model: model)
        var granted = false, requests = 0
        model.listenAccess = { granted }
        model.requestListenAccess = { requests += 1 }
        defer {
            overlay.hide(); model.preferences.value = original; model.session.setHover(false)
            model.listenAccess = { CGPreflightListenEventAccess() }; model.requestListenAccess = {}
            model.refreshScrollAccess()
        }
        model.preferences.value.scrollWheelAnywhere = false
        overlay.show()
        XCTAssertEqual(requests, 0, "no prompt while the option is off")
        model.preferences.value.scrollWheelAnywhere = true
        overlay.updateScrollMonitor()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(overlay.isMonitoringScrollWheel)
        model.refreshScrollAccess()
        XCTAssertFalse(model.scrollAccessGranted)
        granted = true
        model.refreshScrollAccess()
        XCTAssertTrue(model.scrollAccessGranted)
        overlay.updateScrollMonitor(reinstall: true)
        XCTAssertTrue(overlay.isMonitoringScrollWheel)
        XCTAssertEqual(requests, 1)
    }
}
