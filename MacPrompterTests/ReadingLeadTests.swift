import XCTest
import AppKit
@testable import MacPrompter

final class ReadingLeadTests: XCTestCase {
    /// 20 characters per second: one six-character word every 0.3 s.
    private func steadyLead(words: Int = 5, characters: Int = 6) -> ReadingLead {
        var lead = ReadingLead()
        for word in 0...words { lead.confirm(character: Double(word * characters), at: Double(word) * 0.3, jump: false) }
        return lead
    }

    func testGlidesAtSpeakingRateBetweenWords() throws {
        var lead = steadyLead()
        XCTAssertEqual(try XCTUnwrap(lead.rate), 20, accuracy: 0.001)
        lead.advance(by: 0.1, now: 1.6, speaking: true)
        XCTAssertEqual(try XCTUnwrap(lead.estimate), 32, accuracy: 0.001)
    }

    func testLeadIsCappedAndStopsAfterAStall() throws {
        var lead = steadyLead(characters: 10)
        for step in 1...8 { lead.advance(by: 0.1, now: 1.5 + Double(step) * 0.1, speaking: true) }
        XCTAssertEqual(try XCTUnwrap(lead.estimate), 50 + ReadingLead.maxLead, accuracy: 0.001)
        var stalled = steadyLead()
        stalled.advance(by: 0.1, now: 1.5 + ReadingLead.stallAfter + 0.1, speaking: true)
        XCTAssertEqual(try XCTUnwrap(stalled.estimate), 30, accuracy: 0.001)
    }

    func testSilenceDoesNotAdvance() throws {
        var lead = steadyLead()
        lead.advance(by: 0.2, now: 1.7, speaking: false)
        XCTAssertEqual(try XCTUnwrap(lead.estimate), 30, accuracy: 0.001)
    }

    func testNeverMovesBackUnlessReacquired() throws {
        var lead = steadyLead()
        lead.advance(by: 0.5, now: 2.0, speaking: true)
        let ahead = try XCTUnwrap(lead.estimate)
        lead.confirm(character: 36, at: 2.1, jump: false)
        XCTAssertEqual(try XCTUnwrap(lead.estimate), ahead, accuracy: 0.001)
        lead.confirm(character: 6, at: 2.4, jump: true)
        XCTAssertEqual(try XCTUnwrap(lead.estimate), 6, accuracy: 0.001)
        XCTAssertNil(lead.rate, "a re-acquired position starts a new rate")
    }

    func testPauseIsNotPartOfTheSpeakingRate() throws {
        var lead = steadyLead()
        lead.confirm(character: 42, at: 5, jump: false)
        XCTAssertNil(lead.rate)
        lead.advance(by: 0.1, now: 5.1, speaking: true)
        XCTAssertEqual(try XCTUnwrap(lead.estimate), 42, accuracy: 0.001)
    }

    func testVoiceActivityAdaptsToNoiseAndHoldsBriefly() {
        var activity = VoiceActivity()
        var time = 0.0
        for _ in 0..<60 { time += 1.0 / 60; XCTAssertFalse(activity.observe(level: 0.03, at: time, dt: 1.0 / 60)) }
        time += 1.0 / 60
        XCTAssertTrue(activity.observe(level: 0.5, at: time, dt: 1.0 / 60))
        time += VoiceActivity.hold / 2
        XCTAssertTrue(activity.observe(level: 0.03, at: time, dt: VoiceActivity.hold / 2))
        time += VoiceActivity.hold
        XCTAssertFalse(activity.observe(level: 0.03, at: time, dt: VoiceActivity.hold))
    }

    @MainActor
    func testSessionScrollsAheadAtSpeakingPaceOnlyWhenEnabled() throws {
        func run(enabled: Bool) -> (offset: Double, confirmedCharacter: Double, afterStall: Double) {
            let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            preferences.value.mode = .voice
            preferences.value.speechPacedScrolling = enabled
            let session = PrompterSession(preferences: preferences)
            let words = ["Moderne", "Speicher", "liefern", "nachhaltige", "Energie", "für", "unsere", "gemeinsame", "Zukunft", "heute"]
            session.script = Script(title: "Test", body: words.joined(separator: " "))
            session.reset()
            session.maximumOffset = 10_000
            session.voiceGeometry = { $0 * 2 }
            session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
            var frame = 0
            // Speech: loud syllables with short dips, as the input meter reports it.
            func tick(_ count: Int) {
                for _ in 0..<count {
                    frame += 1
                    session.speech.level = frame % 3 == 0 ? 0.04 : 0.6
                    session.advanceReading(by: 0.05)
                }
            }
            for count in 1...6 {
                session.receiveTranscript(words.prefix(count).joined(separator: " "), segment: 0, endTime: Double(count) * 0.35)
                tick(7)
            }
            let confirmed = Double((session.script.body as NSString).range(of: "unsere").location)
            tick(12)
            let offset = session.offset
            tick(40)
            return (offset, confirmed, session.offset)
        }
        let paced = run(enabled: true)
        XCTAssertGreaterThan(paced.offset, paced.confirmedCharacter * 2 + 4, "glides past the confirmed word")
        XCTAssertLessThanOrEqual(paced.afterStall, (paced.confirmedCharacter + ReadingLead.maxLead) * 2 + 0.01, "never more than the lead")
        XCTAssertGreaterThanOrEqual(paced.afterStall, paced.offset, "a stall stops, it does not move back")
        XCTAssertEqual(run(enabled: false).afterStall, 0, "off by default: no reader, no voice destination, no movement")
    }

    @MainActor
    func testContinuousGeometryRisesSmoothlyThroughLines() throws {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: Array(repeating: "Solarmodule liefern nachhaltige Energie für morgen.", count: 12).joined(separator: " "))
        session.reset()
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
        view.update(preferences: preferences.value)
        view.layoutSubtreeIfNeeded()
        let length = (session.script.body as NSString).length
        var previous = -1.0, largestStep = 0.0
        for character in stride(from: 0, to: length, by: 1) {
            let value = try XCTUnwrap(view.continuousVoiceOffset(at: Double(character)))
            XCTAssertGreaterThanOrEqual(value, previous - 0.01, "character \(character)")
            if previous >= 0 { largestStep = max(largestStep, value - previous) }
            previous = value
        }
        XCTAssertGreaterThan(previous, 200)
        XCTAssertLessThan(largestStep, preferences.value.fontSize + preferences.value.lineSpacing, "no full-line jumps")
    }
}
