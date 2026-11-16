import XCTest
import AppKit
@testable import MacPrompter

/// Speech must never scroll pages away by accident (ADR-33): jumps stay
/// within one prompter window, need more evidence the further they go and
/// wait for one more matching word.
final class JumpLimitTests: XCTestCase {
    private let filler = Array(repeating: "Dieser Abschnitt behandelt viele andere interessante Themen.", count: 12).joined(separator: " ")

    func testNeverJumpsBeyondReachEvenWithAPerfectPhrase() {
        var follower = ScriptFollower(text: "Welcome to our studio. \(filler) Solar panels generate renewable electricity every single morning.")
        _ = follower.consume("Welcome to our studio", segment: 0, accepting: true)
        follower.reach = 0...follower.nextIndex + 30
        _ = follower.consume("Can you explain the investment schedule please", segment: 1, accepting: true)
        for (i, phrase) in ["Solar panels generate renewable electricity", "Solar panels generate renewable electricity every",
                            "Solar panels generate renewable electricity every single morning"].enumerated() {
            XCTAssertNil(follower.consume(phrase, segment: 2, accepting: true), "step \(i)")
            XCTAssertEqual(follower.nextIndex, 4)
        }
    }

    func testJumpWithinReachWaitsForOneMoreMatchingWord() {
        var follower = ScriptFollower(text: "Welcome to our studio. \(filler) Solar panels generate renewable electricity every single morning.")
        _ = follower.consume("Welcome to our studio", segment: 0, accepting: true)
        follower.reach = 0...follower.tokens.count - 1
        _ = follower.consume("Can you explain the investment schedule please", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("Solar panels generate renewable electricity", segment: 2, accepting: true))
        XCTAssertNotNil(follower.pendingJump)
        XCTAssertEqual(follower.nextIndex, 4)
        // A revision with the same words is no new evidence.
        XCTAssertNil(follower.consume("solar panels generate renewable electricity", segment: 2, accepting: true))
        XCTAssertNotNil(follower.consume("Solar panels generate renewable electricity every", segment: 2, accepting: true))
        XCTAssertEqual(follower.tokens[follower.nextIndex].normalized, "single")
        XCTAssertNil(follower.pendingJump)
    }

    func testUnrelatedSpeechCancelsAPendingJump() {
        var follower = ScriptFollower(text: "Welcome to our studio. \(filler) Solar panels generate renewable electricity every single morning.")
        _ = follower.consume("Welcome to our studio", segment: 0, accepting: true)
        _ = follower.consume("Can you explain the investment schedule please", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("Solar panels generate renewable electricity", segment: 2, accepting: true))
        XCTAssertNotNil(follower.pendingJump)
        XCTAssertNil(follower.consume("but that is a different story entirely", segment: 3, accepting: true))
        XCTAssertNil(follower.pendingJump)
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testFurtherJumpsNeedMoreMatchingWords() {
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: 0), 4)
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: -20), 4)
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: 48), 4)
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: 49), 5)
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: 97), 6)
        XCTAssertEqual(ScriptFollower.requiredMatches(distance: 5000), 6)
        // 100 words away, four distinctive words are not enough.
        let middle = Array(repeating: "andere Themen", count: 50).joined(separator: " ")
        var follower = ScriptFollower(text: "Willkommen im Studio. \(middle) Solarmodule liefern nachhaltige Energie für alle Haushalte.")
        _ = follower.consume("Willkommen im Studio", segment: 0, accepting: true)
        _ = follower.consume("Das ist eine ganz andere Geschichte", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("Solarmodule liefern nachhaltige Energie", segment: 2, accepting: true))
        XCTAssertNil(follower.pendingJump)
    }

    func testReadingOnWinsOverASimilarDistantSentence() {
        let middle = Array(repeating: "andere Themen", count: 20).joined(separator: " ")
        var follower = ScriptFollower(text: "Willkommen im Studio. Wir sehen uns heute die Zahlen an. \(middle) Wir sehen uns heute die neuen Zahlen genau an.")
        _ = follower.consume("Willkommen im Studio", segment: 0, accepting: true)
        for (i, phrase) in ["Wir sehen", "Wir sehen uns heute", "Wir sehen uns heute die", "Wir sehen uns heute die Zahlen an"].enumerated() {
            _ = follower.consume(phrase, segment: 1, accepting: true)
            XCTAssertLessThanOrEqual(follower.nextIndex, 10, "step \(i)")
        }
        XCTAssertEqual(follower.nextIndex, 10)
    }

    func testWordRangeMapsCharacters() {
        let follower = ScriptFollower(text: "eins zwei drei vier")
        XCTAssertEqual(follower.wordRange(in: 0...4), 0...0)
        XCTAssertEqual(follower.wordRange(in: 0...5), 0...1)
        XCTAssertEqual(follower.wordRange(in: 6...12), 1...2)
        XCTAssertNil(follower.wordRange(in: 100...200))
    }
}

@MainActor
final class SessionJumpLimitTests: XCTestCase {
    private func makeSession(_ body: String) -> PrompterSession {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        preferences.value.predictiveHighlight = false
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: body)
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.systemReducesMotion = { false }
        return session
    }

    private let longScript = "Willkommen im Studio. "
        + Array(repeating: "Ein langer Satz für viele Zeilen mit anderen Themen.", count: 40).joined(separator: " ")
        + " Solarmodule liefern nachhaltige Energie für alle Haushalte jeden Morgen."

    func testWithoutReaderGeometryAJumpStaysBounded() {
        let session = makeSession(longScript)
        session.receiveTranscript("Willkommen im Studio", segment: 0, endTime: 1)
        let highlighted = session.activeWordRange
        session.receiveTranscript("Das ist eine ganz andere Geschichte", segment: 1, endTime: 2)
        for phrase in ["Solarmodule liefern nachhaltige Energie für alle", "Solarmodule liefern nachhaltige Energie für alle Haushalte",
                       "Solarmodule liefern nachhaltige Energie für alle Haushalte jeden Morgen"] {
            session.receiveTranscript(phrase, segment: 2, endTime: 3)
            XCTAssertEqual(session.activeWordRange, highlighted)
        }
        session.hide()
    }

    func testReaderReachIsAboutOneWindowAroundTheReadingLine() async throws {
        let session = makeSession(longScript)
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        let length = (longScript as NSString).length
        let middle = length / 2
        let reach = try XCTUnwrap(view.reachableCharacters(around: middle))
        XCTAssertLessThan(reach.lowerBound, middle)
        XCTAssertGreaterThan(reach.upperBound, middle)
        XCTAssertGreaterThan(reach.lowerBound, 0, "text more than one window above is out of reach")
        XCTAssertLessThan(reach.upperBound, length - 1, "text more than one window below is out of reach")
        // A taller window reaches further.
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        view.layoutSubtreeIfNeeded()
        let taller = try XCTUnwrap(view.reachableCharacters(around: middle))
        XCTAssertGreaterThan(taller.upperBound, reach.upperBound)
        XCTAssertLessThan(taller.lowerBound, reach.lowerBound)
        session.hide()
    }

    func testFarPhraseOutsideTheWindowNeverMovesTheText() async throws {
        let session = makeSession(longScript)
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        session.receiveTranscript("Willkommen im Studio", segment: 0, endTime: 1)
        let highlighted = session.activeWordRange
        session.receiveTranscript("Das ist eine ganz andere Geschichte", segment: 1, endTime: 2)
        for phrase in ["Solarmodule liefern nachhaltige Energie für alle", "Solarmodule liefern nachhaltige Energie für alle Haushalte",
                       "Solarmodule liefern nachhaltige Energie für alle Haushalte jeden Morgen"] {
            session.receiveTranscript(phrase, segment: 2, endTime: 3)
            XCTAssertEqual(session.activeWordRange, highlighted)
        }
        session.hide()
    }
}
