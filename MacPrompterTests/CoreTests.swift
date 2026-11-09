import XCTest
@testable import MacPrompter

final class ScriptTests: XCTestCase {
    func testCuesDoNotCountAsSpeech() {
        let text = "Hallo [Pause] schöne Welt. [Lachen] Hello!"
        XCTAssertEqual(ScriptParser.words(in: text).map(\.normalized), ["hallo", "schone", "welt", "hello"])
        XCTAssertEqual(ScriptParser.cueRanges(in: text).count, 2)
    }
    func testUnicodeRangesPointToOriginalWords() {
        let text = "👋 Grüße [Lächeln] aus Köln!"
        let tokens = ScriptParser.words(in: text)
        XCTAssertEqual((text as NSString).substring(with: tokens[0].range), "Grüße")
        XCTAssertEqual(tokens.map(\.normalized), ["grusse", "aus", "koln"])
    }
    func testUnclosedCueRemainsReadable() {
        XCTAssertEqual(ScriptParser.cueRanges(in: "Hallo [unfertig").count, 0)
        XCTAssertEqual(ScriptParser.words(in: "Hallo [unfertig").count, 2)
    }
    func testGermanAlignmentAndPartialResults() {
        var follower = ScriptFollower(text: "Hallo schöne Welt. [Pause] Grüße aus Köln.")
        XCTAssertNotNil(follower.consume("Hallo schöne", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
        XCTAssertNil(follower.consume("Hallo schöne", segment: 0, accepting: true))
        XCTAssertNotNil(follower.consume("Hallo schöne Welt", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
        XCTAssertNotNil(follower.consume("Grüße aus Köln", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 6)
    }
    func testBackgroundSpeechDoesNotJumpToCommonWord() {
        var follower = ScriptFollower(text: "Hello welcome to our studio. We have a story to tell.")
        XCTAssertNil(follower.consume("the", segment: 0, accepting: true))
        XCTAssertNil(follower.consume("story", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 0)
    }
    func testCanRecoverFromSmallOmission() {
        var follower = ScriptFollower(text: "Today I want to share a simple idea")
        XCTAssertNotNil(follower.consume("share a simple", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 7)
    }
    func testHoverDiscardsTranscriptRatherThanCatchingUp() {
        var follower = ScriptFollower(text: "Hello world welcome back")
        XCTAssertNil(follower.consume("Hello world", segment: 0, accepting: false))
        XCTAssertNil(follower.consume("Hello world", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 0)
        XCTAssertNotNil(follower.consume("Hello world welcome back", segment: 0, accepting: true))
    }
    func testRepeatedPhrasesUseNearestOccurrence() {
        var follower = ScriptFollower(text: "Hello world. Hello world. Hello world.")
        _ = follower.consume("Hello world", segment: 0, accepting: true)
        XCTAssertEqual(follower.nextIndex, 2)
        _ = follower.consume("Hello world", segment: 1, accepting: true)
        XCTAssertEqual(follower.nextIndex, 4)
    }
    func testRecoversAfterHoverWithOneWordPerPartialResult() {
        var follower = ScriptFollower(text: "Hello world welcome back today")
        _ = follower.consume("Hello world", segment: 0, accepting: false)
        XCTAssertNil(follower.consume("Hello world welcome", segment: 0, accepting: true))
        XCTAssertNotNil(follower.consume("Hello world welcome back", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }
    func testSeekSupportsRestartAndEmptyText() {
        var follower = ScriptFollower(text: "One two three")
        _ = follower.consume("One two", segment: 0, accepting: true)
        follower.seek(character: 0)
        XCTAssertEqual(follower.nextIndex, 0)
        var empty = ScriptFollower(text: "[Pause]")
        XCTAssertNil(empty.consume("hello", segment: 0, accepting: true))
    }
    func testHoverOverridesEveryMovementSource() {
        var gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: true, countdown: 0)
        XCTAssertFalse(gate.allowsMovement)
        XCTAssertFalse(gate.allowsAutomaticMovement)
        gate.isHovering = false
        XCTAssertTrue(gate.allowsAutomaticMovement)
        gate.isPlaying = false
        XCTAssertFalse(gate.allowsAutomaticMovement)
        XCTAssertTrue(gate.allowsMovement)
        gate.countdown = 3
        XCTAssertFalse(gate.allowsMovement)
        gate.countdown = 0; gate.isVisible = false
        XCTAssertFalse(gate.allowsMovement)
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    func testRoundTripDoesNotLoseUnicodeOrLanguage() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ScriptLibrary(directory: folder)
        library.add(title: "Über mich 👋", body: "Hello [smile] world")
        library.update(language: .english)
        library.save()
        let restored = ScriptLibrary(directory: folder)
        XCTAssertEqual(restored.scripts.first?.title, "Über mich 👋")
        XCTAssertEqual(restored.scripts.first?.language, .english)
        XCTAssertEqual(restored.scripts.first?.body, "Hello [smile] world")
    }
    func testCorruptLibraryIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "scripts.json")
        let original = Data("broken original".utf8)
        try original.write(to: file)
        let library = ScriptLibrary(directory: folder)
        XCTAssertNotNil(library.errorMessage)
        library.add(title: "test", body: "do not overwrite")
        library.save()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testPauseDoesNotBecomePlayingAfterHoverExit() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = PrompterSession(preferences: PreferenceStore(defaults: defaults))
        session.gate = PlaybackGate(isVisible: true, isPlaying: false, isHovering: true, countdown: 0)
        session.setHover(false)
        XCTAssertFalse(session.gate.isPlaying)
        session.hide()
        XCTAssertFalse(session.gate.isVisible)
        XCTAssertFalse(session.speech.isListening)
    }
}
