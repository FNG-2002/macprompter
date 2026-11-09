import XCTest
import AppKit
@testable import MacPrompter

final class FollowingTests: XCTestCase {
    func testLongAnecdoteHoldsPositionThenFindsScriptAgain() {
        var follower = ScriptFollower(text: "Willkommen in unserem Studio. Heute sprechen wir über nachhaltige Energie und moderne Architektur.")
        _ = follower.consume("Willkommen in unserem Studio", segment: 0, accepting: true)
        let position = follower.nextIndex
        for (i, aside) in ["Das erinnert mich an meinen Urlaub letztes Jahr", "Wir hatten tatsächlich das Flugzeug verpasst", "Wolltest du dazu noch eine Frage stellen"].enumerated() {
            XCTAssertNil(follower.consume(aside, segment: Double(i + 1), accepting: true))
            XCTAssertEqual(follower.nextIndex, position)
        }
        XCTAssertTrue(follower.isOffScript)
        XCTAssertNotNil(follower.consume("Heute sprechen wir über nachhaltige Energie", segment: 5, accepting: true))
        XCTAssertFalse(follower.isOffScript)
        XCTAssertTrue(follower.lastMatch?.reacquired == true)
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "und")
    }

    func testFindsDistantUniquePassageAfterQuestion() {
        let filler = Array(repeating: "Dieser Abschnitt behandelt viele andere interessante Themen.", count: 12).joined(separator: " ")
        var follower = ScriptFollower(text: "Welcome to our studio. \(filler) Solar panels generate renewable electricity every morning.")
        _ = follower.consume("Welcome to our studio", segment: 0, accepting: true)
        _ = follower.consume("Can you explain the investment schedule please", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("Solar panels generate renewable electricity", segment: 2, accepting: true))
        XCTAssertTrue(follower.lastMatch?.reacquired == true)
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "every")
    }

    func testCanReturnToEarlierDistinctiveSentence() {
        let text = "Solar panels generate renewable electricity. Modern batteries store excess energy. Our project has enormous potential."
        var follower = ScriptFollower(text: text)
        _ = follower.consume("Solar panels generate renewable electricity", segment: 0, accepting: true)
        _ = follower.consume("Modern batteries store excess energy", segment: 1, accepting: true)
        _ = follower.consume("Let me explain that earlier point again", segment: 2, accepting: true)
        XCTAssertNotNil(follower.consume("Solar panels generate renewable electricity", segment: 3, accepting: true))
        XCTAssertEqual(follower.nextIndex, 5)
    }

    func testAmbiguousDistantPhraseWaitsForDistinguishingWord() {
        let filler = Array(repeating: "filler", count: 50).joined(separator: " ")
        var follower = ScriptFollower(text: "Welcome friends. \(filler) Solar panels generate renewable electricity today. \(filler) Solar panels generate renewable electricity tomorrow.")
        _ = follower.consume("Welcome friends", segment: 0, accepting: true)
        _ = follower.consume("Let's take a question from our audience", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("Solar panels generate renewable electricity", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
        XCTAssertNotNil(follower.consume("Solar panels generate renewable electricity tomorrow", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, follower.tokens.count)
    }

    func testGenericWordsDoNotRelocateAfterDetour() {
        var follower = ScriptFollower(text: "Welcome everyone. This is what we have here. This is what we have there. Solar panels generate energy.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("My neighbor asked an unrelated question yesterday", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("this is what we have", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testToleratesAnInsertedFillerWord() {
        var follower = ScriptFollower(text: "Solar panels generate renewable electricity every morning.")
        XCTAssertNotNil(follower.consume("Solar panels actually generate renewable electricity", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 5)
    }

    func testToleratesOneSubstitutedWordOnReentry() {
        var follower = ScriptFollower(text: "Welcome friends. Solar panels generate clean renewable electricity every morning.")
        _ = follower.consume("Welcome friends", segment: 0, accepting: true)
        _ = follower.consume("We should answer another audience question first", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("Solar panels generate green renewable electricity", segment: 2, accepting: true))
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "every")
    }

    func testRevisedPartialDoesNotRepeatAlreadyReadPhrase() {
        var follower = ScriptFollower(text: "We build solar panels. We build solar panels. We build modern batteries.")
        _ = follower.consume("We build solar panels", segment: 0, accepting: true)
        let position = follower.nextIndex
        XCTAssertNil(follower.consume("we build solar panels", segment: 0, accepting: true))
        XCTAssertNil(follower.consume("We build solar panel", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, position)
        XCTAssertNil(follower.consume("We build solar panels", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, position)
    }

    func testCorrectingEarlierPartialDoesNotBlockNewWords() {
        var follower = ScriptFollower(text: "Welcome friends. Solar panels generate renewable electricity every morning.")
        _ = follower.consume("Welcome friends", segment: 0, accepting: true)
        _ = follower.consume("Solar panel", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("Solar panels generate renewable electricity", segment: 1, accepting: true))
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "every")
    }

    func testShortClosingPhraseCanResumeAfterAQuestion() {
        var follower = ScriptFollower(text: "Willkommen im Studio. Vielen Dank.")
        _ = follower.consume("Willkommen im Studio", segment: 0, accepting: true)
        _ = follower.consume("Das ist eine sehr interessante Frage aus dem Publikum", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("Vielen Dank", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, follower.tokens.count)
    }

    func testOneWordAtATimeRelocksAfterDetour() {
        var follower = ScriptFollower(text: "Welcome friends. Solar panels generate renewable electricity every morning.")
        _ = follower.consume("Welcome friends", segment: 0, accepting: true)
        _ = follower.consume("I remember a completely unrelated story from school", segment: 1, accepting: true)
        let phrase = ["Solar", "panels", "generate", "renewable", "electricity"]
        for count in 1...phrase.count {
            _ = follower.consume(phrase.prefix(count).joined(separator: " "), segment: 2, accepting: true)
            XCTAssertEqual(follower.nextIndex, 2 + count, "An unambiguous local continuation should not wait for four words")
        }
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "every")
        XCTAssertFalse(follower.isOffScript)
    }

    func testAlreadyReadContextCannotAuthorizeDistantJumpOnOneWord() {
        let filler = Array(repeating: "filler", count: 80).joined(separator: " ")
        var follower = ScriptFollower(text: "Today we discuss solar panels. \(filler) Today we discuss solar power technology.")
        _ = follower.consume("Today we discuss solar", segment: 0, accepting: true)
        XCTAssertNil(follower.consume("power", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testMotionSettlesWithoutOvershootOrNewSpeech() {
        var position = 0.0
        for _ in 0..<120 {
            let next = ReadingMotion.advance(from: position, to: 300, dt: 1.0 / 60, reducedMotion: false)
            XCTAssertGreaterThanOrEqual(next, position)
            XCTAssertLessThanOrEqual(next, 300)
            XCTAssertLessThan(next - position, 37)
            position = next
        }
        XCTAssertEqual(position, 300, accuracy: 0.25)
        XCTAssertEqual(ReadingMotion.advance(from: 300, to: 300, dt: 0.1, reducedMotion: false), 300)
        XCTAssertEqual(ReadingMotion.advance(from: 0, to: 300, dt: 0.1, reducedMotion: true), 300)
    }

    func testLargeBacklogCatchesUpEarlierWithoutOvershoot() {
        var current = 0.0, old = 0.0
        let dt = 1.0 / 120
        for _ in 0..<36 {
            current = ReadingMotion.advance(from: current, to: 300, dt: dt, reducedMotion: false)
            old += min(2200 * dt, (300 - old) * (1 - exp(-dt / 0.18)))
        }
        XCTAssertGreaterThan(current, old + 15)
        XCTAssertLessThan(current, 300)
        for rate in [30.0, 60, 120, 144] {
            var value = 300.0
            for _ in 0..<Int(rate) {
                let next = ReadingMotion.advance(from: value, to: 0, dt: 1 / rate, reducedMotion: false)
                XCTAssertLessThanOrEqual(next, value)
                XCTAssertGreaterThanOrEqual(next, 0)
                value = next
            }
            XCTAssertLessThan(value, 0.5)
        }
    }

    func testMotionIsIndependentOfFrameRate() {
        func moved(_ rate: Double) -> Double {
            var value = 0.0
            for _ in 0..<Int(rate) { value = ReadingMotion.advance(from: value, to: 200, dt: 1 / rate, reducedMotion: false) }
            return value
        }
        XCTAssertEqual(moved(30), moved(120), accuracy: 0.1)
    }
}

@MainActor
final class ReadingSessionTests: XCTestCase {
    private func makeSession(_ body: String) -> PrompterSession {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: body)
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.systemReducesMotion = { false }
        return session
    }

    func testHighlightsOnlyRecognizedWordsAndKeepsLastDuringSilence() {
        let session = makeSession("Hello brave world. Next line.")
        session.receiveTranscript("Hello brave", segment: 0, endTime: 1)
        XCTAssertEqual(session.activeWordRange, NSRange(location: 6, length: 5))
        session.advanceReading(by: 0.08)
        XCTAssertEqual(session.activeWordRange, NSRange(location: 6, length: 5))
        for _ in 0..<100 { session.advanceReading(by: 0.016) }
        XCTAssertEqual(session.activeWordRange, NSRange(location: 6, length: 5))
        session.hide()
    }

    func testSystemReduceMotionJumpsDirectlyToDestination() {
        let session = makeSession("Hello world next line")
        session.systemReducesMotion = { true }
        session.maximumOffset = 500
        session.resolveVoiceDestination(300, for: session.targetCharacter!)
        session.advanceReading(by: 0.016)
        XCTAssertEqual(session.offset, 300)
        session.hide()
    }

    func testHoverAndManualPauseStopSettlingImmediately() {
        let session = makeSession("Hello world next line")
        session.maximumOffset = 500
        session.resolveVoiceDestination(300, for: session.targetCharacter!)
        session.advanceReading(by: 0.016)
        XCTAssertGreaterThan(session.offset, 0)
        XCTAssertLessThan(session.offset, 300)
        session.setHover(true)
        let frozen = session.offset
        session.advanceReading(by: 0.1)
        XCTAssertEqual(session.offset, frozen)
        session.setHover(false)
        session.advanceReading(by: 0.1)
        XCTAssertEqual(session.offset, frozen)
        session.pause()
        session.advanceReading(by: 0.1)
        XCTAssertEqual(session.offset, frozen)
        session.hide()
    }

    func testCueGapRevealsUpcomingSpeechThenStops() async throws {
        let session = makeSession("Hallo.\n\n[Pause]\n\n[Lächeln]\n\nHier geht unsere Geschichte weiter.")
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        session.receiveTranscript("Hallo", segment: 0, endTime: 1)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        let destination = try XCTUnwrap(session.voiceDestination)
        XCTAssertGreaterThan(destination, 0)
        XCTAssertEqual(session.offset, 0, "A transcript must not teleport the viewport")
        for _ in 0..<150 { session.advanceReading(by: 1.0 / 60) }
        XCTAssertEqual(session.offset, destination, accuracy: 0.3)
        let settled = session.offset
        for _ in 0..<150 { session.advanceReading(by: 1.0 / 60) }
        XCTAssertEqual(session.offset, settled, accuracy: 0.3)
        XCTAssertEqual(session.activeWordRange, NSRange(location: 0, length: 5))
        session.hide()
    }

    func testWordHighlightUsesTemporaryAttributesWithoutRelayout() throws {
        let session = makeSession("Hallo [Pause] schöne Welt")
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        session.receiveTranscript("Hallo", segment: 0, endTime: 1)
        view.update(preferences: session.preferences.value)
        let clip = try XCTUnwrap(view.subviews.first as? NSClipView)
        let text = try XCTUnwrap(clip.documentView as? NSTextView)
        let manager = try XCTUnwrap(text.layoutManager)
        XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: 8, effectiveRange: nil))
        let plain = text.textStorage!.attribute(.foregroundColor, at: 20, effectiveRange: nil) as! NSColor
        XCTAssertNotEqual(plain, NSColor.white)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = FileManager.default.temporaryDirectory.appending(path: "macprompter-word-highlight.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        print("WORD_SNAPSHOT: \(url.path)")
        session.hide()
    }
}
