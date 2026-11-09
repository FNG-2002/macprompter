import XCTest
@testable import MacPrompter

/// Spellings measured with SpeechTranscriber on 27 October 2026: small numbers
/// as words, larger ones as digits, "Dr." for "Doktor", "25%" and "email" in
/// English, spelled-out "zum Beispiel" in German.
final class LexicalBridgeTests: XCTestCase {
    /// Feeds growing volatile results of one segment, like `.fastResults`,
    /// and returns the position after every heard word.
    private func trace(_ script: String, _ heard: String) -> [Int] {
        var follower = ScriptFollower(text: script)
        let words = heard.split(separator: " ")
        return (1...words.count).map { count in
            _ = follower.consume(words[..<count].joined(separator: " "), segment: 0, accepting: true)
            return follower.nextIndex
        }
    }

    func testSmallNumberHeardAsWordFollowsWithoutLag() {
        XCTAssertEqual(trace("Wir planen 3 Schritte für morgen.", "Wir planen drei Schritte für morgen"), [1, 2, 3, 4, 5, 6])
    }

    func testSpelledOutNumberHeardAsDigits() {
        XCTAssertEqual(trace("Wir sparen fünfundzwanzig Prozent der Kosten.", "Wir sparen 25 Prozent der Kosten"), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(trace("Im Jahr zweitausendsechsundzwanzig kamen Gäste.", "Im Jahr 2026 kamen Gäste"), [1, 2, 3, 4, 5])
    }

    func testEnglishMultiWordNumberAndPercentSign() {
        XCTAssertEqual(trace("We save twenty-five percent of the cost.", "We save 25% of the cost"), [1, 2, 5, 6, 7, 8])
        XCTAssertEqual(trace("We had one hundred twelve customers last year.", "We had 112 customers last year"), [1, 2, 5, 6, 7, 8])
    }

    func testPercentSignInScriptIgnoresSpokenPercentWord() {
        XCTAssertEqual(trace("Wir sparen 25 % der Kosten.", "Wir sparen 25 Prozent der Kosten"), [1, 2, 3, 3, 4, 5])
    }

    func testAbbreviationsAndTitles() {
        XCTAssertEqual(trace("Heute schreibt Doktor Müller einen Brief.", "Heute schreibt Dr. Müller einen Brief"), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(trace("Wir nutzen z. B. eine Wärmepumpe im Keller.", "Wir nutzen zum Beispiel eine Wärmepumpe im Keller"), [1, 2, 2, 4, 5, 6, 7, 8])
    }

    func testHyphenatedAndCompoundWords() {
        XCTAssertEqual(trace("Die Solar-Module liefern Strom.", "Die Solarmodule liefern Strom"), [1, 3, 4, 5])
        XCTAssertEqual(trace("Please send an e-mail today.", "Please send an email today"), [1, 2, 3, 5, 6])
        XCTAssertEqual(trace("Unsere Solarmodule liefern Strom.", "Unsere Solar-Module liefern Strom"), [1, 2, 3, 4])
    }

    func testContractions() {
        XCTAssertEqual(trace("We do not stop here today.", "We don't stop here today"), [1, 3, 4, 5, 6])
        XCTAssertEqual(trace("Don't stop here today.", "Do not stop here today"), [0, 1, 2, 3, 4])
    }

    func testInflectedOrMisheardWordNearTheExpectedPosition() {
        XCTAssertEqual(trace("Moderne Speicher liefern nachhaltige Energie.", "Moderne Speichern liefern nachhaltige Energie"), [1, 2, 3, 4, 5])
        XCTAssertEqual(trace("The batteries store clean energy for tomorrow.", "The battery store clean energy for tomorrow"), [1, 2, 3, 4, 5, 6, 7])
    }

    func testNearMissNeverReacquiresWhileOffScript() {
        var follower = ScriptFollower(text: "Willkommen im Studio. Moderne Speicher liefern nachhaltige Energie.")
        _ = follower.consume("Willkommen im Studio", segment: 0, accepting: true)
        _ = follower.consume("Das erinnert mich an meinen letzten Urlaub", segment: 1, accepting: true)
        XCTAssertTrue(follower.isOffScript)
        XCTAssertNil(follower.consume("Speichern", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
    }

    func testWordThatExistsInScriptIsNeverRewritten() {
        var follower = ScriptFollower(text: "Wir speichern Daten sicher. Danach kommen moderne Speicher zum Einsatz.")
        _ = follower.consume("Wir speichern Daten sicher Danach kommen moderne", segment: 0, accepting: true)
        XCTAssertEqual(follower.nextIndex, 7)
        XCTAssertNil(follower.consume("speichern", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 7)
    }

    func testWhitespaceSeparatedScriptWordsAreNotMerged() {
        XCTAssertEqual(trace("Wir gehen an der Wand entlang.", "Wir gehen ander"), [1, 2, 2])
    }

    func testDistantNumberAloneDoesNotRelocate() {
        let filler = Array(repeating: "Dieser Abschnitt behandelt andere Themen.", count: 12).joined(separator: " ")
        var follower = ScriptFollower(text: "Willkommen zusammen. \(filler) Wir sparen 25 Prozent.")
        _ = follower.consume("Willkommen zusammen", segment: 0, accepting: true)
        XCTAssertNil(follower.consume("fünfundzwanzig", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testSemanticEvidenceKeepsHeardSurfaceWithoutPlaceholders() {
        var follower = ScriptFollower(text: "Bitte eine E-Mail schreiben. Danach folgt etwas völlig anderes.")
        _ = follower.consume("Bitte eine", segment: 0, accepting: true)
        _ = follower.consume("Email an meinen Kollegen in Berlin", segment: 1, accepting: true)
        XCTAssertFalse(follower.semanticEvidence().contains(""))
    }

    func testNumberParsing() {
        XCTAssertEqual(LexicalBridge.number(["zweitausendsechsundzwanzig"]), 2026)
        XCTAssertEqual(LexicalBridge.number(["einhundertzwolf"]), 112)
        XCTAssertEqual(LexicalBridge.number(["tausend"]), 1000)
        XCTAssertEqual(LexicalBridge.number(["dreissig"]), 30)
        XCTAssertEqual(LexicalBridge.number(["twenty", "five"]), 25)
        XCTAssertEqual(LexicalBridge.number(["one", "hundred", "and", "twelve"]), 112)
        XCTAssertEqual(LexicalBridge.number(["2026"]), 2026)
        for word in [["five", "twenty"], ["twenty", "twelve"], ["hunderte"], ["grund"], ["ein"], ["jahrtausend"], ["one", "and"]] {
            XCTAssertNil(LexicalBridge.number(word), word.joined(separator: " "))
        }
    }

    func testNearMissRules() {
        XCTAssertTrue(LexicalBridge.isNearMiss("speichern", of: "speicher"))
        XCTAssertTrue(LexicalBridge.isNearMiss("liefert", of: "liefern"))
        XCTAssertTrue(LexicalBridge.isNearMiss("battery", of: "batteries"))
        XCTAssertFalse(LexicalBridge.isNearMiss("kontrolle", of: "kontrakt"))
        XCTAssertFalse(LexicalBridge.isNearMiss("energie", of: "energiewende"))
        XCTAssertFalse(LexicalBridge.isNearMiss("haus", of: "maus"))
        XCTAssertFalse(LexicalBridge.isNearMiss("winter", of: "sinter"))
    }

    /// `.fastResults` often ends a partial result with a word being spoken.
    func testTrailingPartialWordDoesNotHoldBackCompleteWords() {
        var follower = ScriptFollower(text: "Heute zeige ich euch, wie moderne Speicher nachhaltige Energie liefern und warum das für unsere Zukunft wichtig ist.")
        let stream = [
            "Heute zeige ich euch wie", "Heute zeige ich euch wie Moder", "Heute zeige ich euch wie moderne Spei",
            "Heute zeige ich euch wie moderne Speicher nach", "Heute zeige ich euch wie moderne Speicher nachhaltige",
            "Heute zeige ich euch wie moderne Speicher nachhaltige Energien lief",
            "Heute zeige ich euch wie moderne Speicher nachhaltige Energie liefern und war"
        ]
        let next = stream.map { text -> String in
            _ = follower.consume(text, segment: 0, accepting: true)
            return follower.tokens[follower.nextIndex].normalized
        }
        XCTAssertEqual(next, ["moderne", "moderne", "speicher", "nachhaltige", "energie", "liefern", "warum"])
    }

    func testTrailingFragmentAfterAnAsideDoesNotRelocate() {
        var follower = ScriptFollower(text: "Willkommen im Studio. Moderne Speicher liefern Energie. Später sprechen wir über Kosten und Kaffee.")
        _ = follower.consume("Willkommen im Studio", segment: 0, accepting: true)
        XCTAssertNil(follower.consume("Ich trinke morgens gerne einen Kaff", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
        XCTAssertNil(follower.consume("Ich trinke morgens gerne einen Kaffee mit Milch", segment: 1, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
    }
}
