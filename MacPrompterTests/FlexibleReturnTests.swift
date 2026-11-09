import XCTest
@testable import MacPrompter

final class FlexibleReturnTests: XCTestCase {
    private func afterAside(_ body: String) -> ScriptFollower {
        var follower = ScriptFollower(text: "Welcome everyone. " + body)
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("That reminds me of an unrelated story from my vacation", segment: 1, accepting: true)
        return follower
    }

    private func assertLastWord(_ word: String, _ follower: ScriptFollower, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(follower.lastMatch?.wordIndices.last.map { follower.tokens[$0].normalized }, word, file: file, line: line)
    }

    func testChangedGermanSentenceBeginningResumesOnTwoAnchors() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNotNil(follower.consume("Danach schauen wir auf die Kosten und prüfen", segment: 2, accepting: true))
        assertLastWord("prufen", follower)
    }

    func testChangedEnglishBeginningAndInsertedWord() {
        var follower = afterAside("Next we compare the costs and examine the results carefully.")
        XCTAssertNotNil(follower.consume("Then we look at costs and briefly examine", segment: 2, accepting: true))
        assertLastWord("examine", follower)
    }

    func testOmittedAndReplacedWordsBetweenAnchors() {
        var follower = afterAside("Jetzt prüfen wir die Kosten unserer bisherigen Planung und die Ergebnisse.")
        XCTAssertNotNil(follower.consume("Wir betrachten Kosten der neuen Planung und Ergebnisse", segment: 2, accepting: true))
        assertLastWord("ergebnisse", follower)
    }

    func testTrailingSpokenAsideDoesNotBlockConfirmedPosition() {
        var follower = afterAside("Als Nächstes vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNotNil(follower.consume("Die Kosten und prüfen würde ich sagen", segment: 2, accepting: true))
        assertLastWord("prufen", follower)
        let position = follower.nextIndex
        XCTAssertNil(follower.consume("Die Kosten und prüfen würde ich sagen heute", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, position, "Old anchors must not be reused by a later trailing word")
    }

    func testPartialResultsCanBuildReturnEvidence() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Danach schauen wir auf die Kosten", segment: 2, accepting: true))
        XCTAssertNotNil(follower.consume("Danach schauen wir auf die Kosten und prüfen", segment: 2, accepting: true))
        assertLastWord("prufen", follower)
    }

    func testReturnEvidenceSpansRecognitionSegments() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Danach schauen wir auf die Kosten", segment: 2, accepting: true))
        XCTAssertNotNil(follower.consume("und prüfen", segment: 3, accepting: true))
        assertLastWord("prufen", follower)
    }

    func testSingleCoincidentalAnchorDoesNotMove() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Im Urlaub waren die Kosten wirklich enorm", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testReversedAnchorsDoNotMove() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Wir müssen prüfen welche Kosten entstehen", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testScatteredAnecdoteAnchorsDoNotMove() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Kosten waren damals ein Problem im Urlaub und prüfen konnte das niemand", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testAmbiguousLocalPhrasesWait() {
        var follower = afterAside("Wir betrachten Kosten und Ergebnisse heute sowie Kosten und Ergebnisse morgen.")
        XCTAssertNil(follower.consume("Kosten sowie Ergebnisse", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testSixteenWordBoundaryPreventsLargerJump() {
        let lead = Array(repeating: "anderes", count: 16).joined(separator: " ")
        var follower = afterAside(lead + " Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Kosten und kurz prüfen", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testLargerLocalGapNeedsThreeAnchors() {
        var follower = afterAside("Nach einer kurzen Zusammenfassung unserer bisherigen sehr ausführlichen Planung prüfen Teams die Kosten und bewerten Ergebnisse.")
        XCTAssertNil(follower.consume("Planung prüfen", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
        XCTAssertNotNil(follower.consume("Planung prüfen Kosten bewerten", segment: 2, accepting: true))
        assertLastWord("bewerten", follower)
    }

    func testLongTrailingAsideDoesNotUseStaleAnchors() {
        var follower = afterAside("Als Nächstes vergleichen wir die Kosten und prüfen die Ergebnisse.")
        XCTAssertNil(follower.consume("Kosten und prüfen erinnert mich gerade an meinen Urlaub", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testCorrectedAnchorCannotContributeToReturn() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        _ = follower.consume("Danach Kosten", segment: 2, accepting: true)
        XCTAssertNil(follower.consume("Danach Preise und prüfen", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testHoverDiscardsFlexibleReturnEvidence() {
        var follower = afterAside("Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.")
        _ = follower.consume("Kosten und", segment: 2, accepting: false)
        XCTAssertNil(follower.consume("Kosten und prüfen", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testUnseenCookingAndTravelPhrases() {
        for (script, spoken, last) in [
            ("Im nächsten Schritt schneiden wir Tomaten und würzen die Soße.", "Danach kommen Tomaten hinein und würzen wir", "wurzen"),
            ("After the break we explore gardens and photograph historic buildings.", "Later we visit gardens then photograph some", "photograph")
        ] {
            var follower = afterAside(script)
            XCTAssertNotNil(follower.consume(spoken, segment: 2, accepting: true), spoken)
            assertLastWord(last, follower)
        }
    }
}
