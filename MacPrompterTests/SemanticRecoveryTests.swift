import XCTest
@testable import MacPrompter

final class SemanticRecoveryTests: XCTestCase {
    func testAppleModelsHandleLocalParaphrasesAndRejectUnrelatedAsides() async throws {
        let engine = AppleSemanticRecovery()
        let cases: [(SpeechLanguage, String, String, String)] = [
            (.german, "Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.", "Nun kontrollieren wir die Ergebnisse", "ergebnisse"),
            (.english, "Next we compare the costs and examine the results.", "Now we check the results", "results")
        ]
        for (language, script, spoken, last) in cases {
            guard await engine.available(for: language) else { throw XCTSkip("Apple-Satzmodell lokal nicht verfügbar") }
            let windows = SemanticCandidates.windows(text: script, nextIndex: 0)
            _ = await engine.evaluate(SemanticRecoveryRequest(revision: 0, nextIndex: 0, language: language, heard: [], windows: windows))
            let result = await engine.evaluate(SemanticRecoveryRequest(revision: 1, nextIndex: 0, language: language,
                heard: spoken.split(separator: " ").map(String.init), windows: windows))
            let index = try XCTUnwrap(result.wordIndex, "\(language): similarity \(result.similarity)")
            XCTAssertEqual(ScriptParser.words(in: script)[index].normalized, last)
            print("APPLE_SEMANTIC \(language.rawValue) similarity=\(result.similarity) warm_ms=\(result.milliseconds)")
            let unrelated = language == .german ? "Im Urlaub waren leider die Kosten höher" : "My holiday unexpectedly had higher costs"
            let rejected = await engine.evaluate(SemanticRecoveryRequest(revision: 2, nextIndex: 0, language: language,
                heard: unrelated.split(separator: " ").map(String.init), windows: windows))
            XCTAssertNil(rejected.wordIndex)
        }
    }

    func testAppleModelsFindReturnAfterUnrelatedPrefix() async throws {
        let engine = AppleSemanticRecovery()
        let cases: [(SpeechLanguage, String, String)] = [
            (.german, "Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.",
             "Im Urlaub gab es eine lustige Überraschung Nun kontrollieren wir die Ergebnisse"),
            (.english, "Next we compare the costs and examine the results.",
             "My vacation had a rather surprising ending Now let's verify our results")
        ]
        for (language, script, spoken) in cases {
            guard await engine.available(for: language) else { throw XCTSkip("Apple-Satzmodell nicht verfügbar") }
            let heard = Array(ScriptParser.words(in: spoken).map { (spoken as NSString).substring(with: $0.range) }.suffix(12))
            let windows = SemanticCandidates.windows(text: script, nextIndex: 0)
            let result = await engine.evaluate(SemanticRecoveryRequest(revision: 1, nextIndex: 0,
                language: language, heard: heard, windows: windows))
            XCTAssertEqual(result.wordIndex, ScriptParser.words(in: script).count - 1, "\(language): \(result.similarity)")
        }
    }

    func testShortReturnDoesNotDropNegationOrAcceptUnrelatedEnding() async throws {
        let engine = AppleSemanticRecovery()
        let cases: [(SpeechLanguage, String, [String])] = [
            (.german, "Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.", [
                "Wir sollten nicht wie damals handeln Nun kontrollieren wir die Ergebnisse",
                "Das erinnert mich an meinen Urlaub eine andere Geschichte über Ergebnisse",
                "Das war damals ein großer Zufall Nun kontrollieren wir keine Ergebnisse"
            ]),
            (.english, "Next we compare the costs and examine the results.", [
                "We should not do this today Now let's verify our results",
                "I remember my holidays and dreamed about completely different results",
                "Let me explain this little anecdote we aren't checking these results"
            ])
        ]
        for (language, script, spokenCases) in cases {
            guard await engine.available(for: language) else { throw XCTSkip("Apple-Satzmodell nicht verfügbar") }
            for spoken in spokenCases {
                let heard = Array(spoken.split(separator: " ").map(String.init).suffix(12))
                let result = await engine.evaluate(SemanticRecoveryRequest(revision: 1, nextIndex: 0,
                    language: language, heard: heard, windows: SemanticCandidates.windows(text: script, nextIndex: 0)))
                XCTAssertNil(result.wordIndex, "\(spoken): \(result.similarity)")
            }
        }
    }

    func testReturnTailRequiresLongEnoughContextAndPreservesNegations() {
        XCTAssertNil(SemanticCandidates.returnTail(heard: ["Now", "let's", "verify", "our", "results"]))
        XCTAssertNil(SemanticCandidates.returnTail(heard: ["earlier", "today", "not", "Now", "let's", "verify", "our", "results"]))
        XCTAssertNil(SemanticCandidates.returnTail(heard: ["earlier", "today", "somewhere", "and", "we", "have", "the", "results"]))
        XCTAssertEqual(SemanticCandidates.returnTail(heard: ["earlier", "today", "somewhere", "Now", "let's", "verify", "our", "results"]),
            ["Now", "let's", "verify", "our", "results"])
    }

    func testSharedAnchorMustBeRecentDistinctiveAndUnambiguous() {
        let windows = SemanticCandidates.windows(text: "Wir vergleichen die Kosten und prüfen die Ergebnisse. Danach vergleichen wir Kosten für andere Projekte.", nextIndex: 0)
        XCTAssertFalse(windows.isEmpty)
        XCTAssertNil(SemanticCandidates.anchor(heard: ["Heute", "reden", "wir", "über", "Kosten"], window: windows[0], allWindows: windows))
        XCTAssertNil(SemanticCandidates.anchor(heard: ["die", "und", "wir", "heute"], window: windows[0], allWindows: windows))
        XCTAssertNil(SemanticCandidates.anchor(heard: ["Ergebnisse", "machen", "das", "heute", "sehr", "interessant"], window: windows[0], allWindows: windows))
    }

    func testNegationDoesNotCountAsPositiveParaphrase() {
        let windows = SemanticCandidates.windows(text: "Wir überprüfen jetzt die Ergebnisse.", nextIndex: 0)
        XCTAssertNil(SemanticCandidates.anchor(heard: ["Wir", "kontrollieren", "nicht", "die", "Ergebnisse"], window: windows[0], allWindows: windows))
    }

    func testPreparedIndexPreservesSentencesCuesAndPositions() {
        let index = SemanticScriptIndex(text: "Alpha beta gamma delta. [Pause] Epsilon zeta eta theta. Iota kappa lambda mu.")
        let windows = index.windows(nextIndex: 0)
        XCTAssertEqual(windows.map(\.startIndex), [0, 4, 8])
        XCTAssertEqual(windows.map(\.text), ["Alpha beta gamma delta", "Epsilon zeta eta theta", "Iota kappa lambda mu"])
        XCTAssertEqual(index.windows(nextIndex: 4).map(\.startIndex), [4, 8])
        XCTAssertTrue(index.windows(nextIndex: -1).isEmpty)
        XCTAssertTrue(index.windows(nextIndex: 12).isEmpty)
        XCTAssertTrue(SemanticScriptIndex(text: "[Pause]").windows(nextIndex: 0).isEmpty)
    }

    func testCandidatesStayWithinTwentyFourWordsAndExcludeCues() {
        let body = "[Pause] " + (0..<60).map { "wort\($0)" }.joined(separator: " ")
        let windows = SemanticCandidates.windows(text: body, nextIndex: 4)
        XCTAssertLessThanOrEqual(windows.count, 4)
        for window in windows {
            XCTAssertGreaterThanOrEqual(window.startIndex, 4)
            XCTAssertLessThanOrEqual(window.startIndex + window.words.count, 28)
            XCTAssertFalse(window.text.contains("Pause"))
        }
    }

    func testSemanticEvidenceExcludesConsumedAndPausedSpeech() {
        var follower = ScriptFollower(text: "Hallo Welt. Anschließend prüfen wir die Ergebnisse.")
        _ = follower.consume("Hallo Welt", segment: 0, accepting: true)
        XCTAssertTrue(follower.semanticEvidence().isEmpty)
        _ = follower.consume("Das war übrigens völlig anders", segment: 1, accepting: true)
        XCTAssertEqual(follower.semanticEvidence(), ["Das", "war", "übrigens", "völlig", "anders"])
        _ = follower.consume("Das war übrigens völlig anders gestern", segment: 1, accepting: false)
        XCTAssertTrue(follower.semanticEvidence().isEmpty)
        _ = follower.consume("Das war übrigens völlig anders gestern und heute", segment: 1, accepting: true)
        XCTAssertEqual(follower.semanticEvidence(), ["und", "heute"])
    }
}

private actor DelayedSemanticEngine: SemanticRecovering {
    private(set) var calls = 0
    let availableValue: Bool
    let delay: Duration
    init(available: Bool = true, delay: Duration = .milliseconds(40)) {
        availableValue = available; self.delay = delay
    }
    func available(for language: SpeechLanguage) -> Bool { availableValue }
    func evaluate(_ request: SemanticRecoveryRequest) async -> SemanticRecoveryEvaluation {
        calls += 1
        try? await Task.sleep(for: delay)
        let anchor = request.windows.compactMap { SemanticCandidates.anchor(heard: request.heard, window: $0, allWindows: request.windows) }.last
        return SemanticRecoveryEvaluation(available: availableValue, wordIndex: availableValue ? anchor : nil, similarity: 0.9, milliseconds: 40)
    }
}

@MainActor
final class SemanticSessionTests: XCTestCase {
    private let body = "Welcome everyone. Next we compare the costs and examine the results. Afterward we start another topic."
    private let spoken = "Now let's verify our results"

    private func session(engine: any SemanticRecovering, mode: PlaybackMode = .voice) -> PrompterSession {
        let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.value.mode = mode
        let session = PrompterSession(preferences: prefs, semanticEngine: engine)
        session.script = Script(title: "Test", body: body, language: .english)
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.receiveTranscript("Welcome everyone", segment: 0, endTime: 1)
        return session
    }

    /// Both switches were removed (ADR-22); stored values must not break or
    /// reset the remaining preferences.
    func testRemovedSettingsInStoredPreferencesAreIgnored() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let original = PreferenceStore(defaults: defaults)
        original.value.fontSize = 21; original.value.docked = false; original.value.mode = .voice
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: "preferences.v1"))) as? [String: Any])
        dictionary["semanticRecoveryEnabled"] = false
        dictionary["dictationRecognition"] = false
        defaults.set(try JSONSerialization.data(withJSONObject: dictionary), forKey: "preferences.v1")
        let restored = PreferenceStore(defaults: defaults)
        XCTAssertEqual(restored.value.fontSize, 21)
        XCTAssertFalse(restored.value.docked)
        XCTAssertEqual(restored.value.mode, .voice)
        restored.value.fontSize = 22
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: "preferences.v1"))) as? [String: Any])
        XCTAssertNil(saved["semanticRecoveryEnabled"])
        XCTAssertNil(saved["dictationRecognition"])
    }

    func testOnlyVoiceModeCallsModel() async {
        let engine = DelayedSemanticEngine()
        let session = session(engine: engine, mode: .manual)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        await session.semanticTask?.value
        let calls = await engine.calls
        XCTAssertEqual(calls, 0)
        session.hide()
    }

    func testRealAppleModelOnlyMarksSpokenAnchorAndIsCounted() async throws {
        let engine = AppleSemanticRecovery()
        guard await engine.available(for: .english) else { throw XCTSkip("Apple-Satzmodell nicht verfügbar") }
        let session = session(engine: engine)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        XCTAssertNotNil(session.semanticTask, "The fixture must exercise the model, not the lexical tracker")
        await session.semanticTask?.value
        XCTAssertEqual(session.activeWordRange, (body as NSString).range(of: "results"))
        XCTAssertEqual(session.speechLatency.semanticReturns, 1)
        session.hide()
    }

    func testFullSessionFindsParaphrasedReturnAfterAsideInBothLanguages() async throws {
        let engine = AppleSemanticRecovery()
        let cases: [(SpeechLanguage, String, String, String)] = [
            (.german, "Hallo zusammen. Anschließend vergleichen wir die Kosten und prüfen sämtliche Ergebnisse.",
             "Hallo zusammen", "Im Urlaub gab es eine lustige Überraschung Jetzt überprüfen wir die Ergebnisse"),
            (.english, body, "Welcome everyone",
             "My vacation had a rather surprising ending Now let's verify our results")
        ]
        for (language, script, prefix, heard) in cases {
            guard await engine.available(for: language) else { throw XCTSkip("Apple-Satzmodell nicht verfügbar") }
            let prefs = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            prefs.value.mode = .voice
            let session = PrompterSession(preferences: prefs, semanticEngine: engine)
            session.script = Script(title: "Test", body: script, language: language)
            session.reset()
            session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
            session.receiveTranscript(prefix, segment: 0, endTime: 1)
            let old = session.activeWordRange
            session.receiveTranscript(heard, segment: 2, endTime: 3)
            XCTAssertEqual(session.activeWordRange, old, "Must exercise semantic fallback")
            XCTAssertNotNil(session.semanticTask)
            await session.semanticTask?.value
            let anchor = language == .german ? "Ergebnisse" : "results"
            XCTAssertEqual(session.activeWordRange, (script as NSString).range(of: anchor))
            session.hide()
        }
    }

    func testUnavailableModelLeavesNormalFollowingUsable() async {
        let session = session(engine: DelayedSemanticEngine(available: false))
        let old = session.activeWordRange
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        await session.semanticTask?.value
        XCTAssertEqual(session.activeWordRange, old)
        XCTAssertEqual(session.semanticEnglishAvailable, false)
        session.receiveTranscript("Next we compare the costs", segment: 3, endTime: 4)
        XCTAssertEqual(session.activeWordRange, (body as NSString).range(of: "costs"))
        session.hide()
    }

    func testDelayedResultCannotOverrideHoverPauseSeekOrManualMove() async throws {
        for action in 0..<5 {
            let engine = DelayedSemanticEngine()
            let session = session(engine: engine)
            session.receiveTranscript(spoken, segment: 2, endTime: 3)
            try await Task.sleep(for: .milliseconds(10))
            let calls = await engine.calls
            XCTAssertEqual(calls, 1)
            switch action {
            case 0: session.setHover(true)
            case 1: session.pause()
            case 2: session.seekVoice(to: 0)
            case 3: session.nudge(10)
            default: session.hide()
            }
            let old = session.activeWordRange
            await session.semanticTask?.value
            XCTAssertEqual(session.activeWordRange, old)
            session.hide()
        }
    }

    func testNewLexicalProgressWinsOverPendingModel() async throws {
        let engine = DelayedSemanticEngine()
        let session = session(engine: engine)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(10))
        session.receiveTranscript("Next we compare the costs", segment: 3, endTime: 4)
        let expected = session.activeWordRange
        await session.semanticTask?.value
        XCTAssertEqual(session.activeWordRange, expected)
        XCTAssertEqual(expected, (body as NSString).range(of: "costs"))
        session.hide()
    }
    func testExpiredResultCannotMoveCursor() async {
        let engine = DelayedSemanticEngine(delay: .milliseconds(300))
        let session = session(engine: engine)
        let old = session.activeWordRange
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        XCTAssertNotNil(session.semanticTask)
        await session.semanticTask?.value
        XCTAssertEqual(session.activeWordRange, old)
        session.hide()
    }

    func testRapidPartialsKeepOnlyLatestPendingEvaluation() async throws {
        let engine = DelayedSemanticEngine()
        let session = session(engine: engine)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(10))
        let startedCalls = await engine.calls
        XCTAssertEqual(startedCalls, 1)
        for i in 0..<15 {
            session.receiveTranscript("Now " + Array(repeating: "please", count: i % 3 + 1).joined(separator: " ") + " verify our results", segment: 2, endTime: 4)
        }
        await session.semanticTask?.value
        let calls = await engine.calls
        XCTAssertEqual(calls, 2)
        session.hide()
    }

    func testDuplicateTranscriptKeepsInFlightAnswerWithoutExtraEvaluation() async throws {
        for duplicate in [spoken, "NOW, let's verify our results!"] {
            let engine = DelayedSemanticEngine()
            let session = session(engine: engine)
            session.receiveTranscript(spoken, segment: 2, endTime: 3)
            try await Task.sleep(for: .milliseconds(10))
            session.receiveTranscript(duplicate, segment: 2, endTime: 3.1)
            await session.semanticTask?.value
            XCTAssertEqual(session.activeWordRange, (body as NSString).range(of: "results"))
            session.receiveTranscript(duplicate, segment: 2, endTime: 3.2)
            await session.semanticTask?.value
            let calls = await engine.calls
            XCTAssertEqual(calls, 1)
            session.hide()
        }
    }

    func testDuplicateKeepsLatestPendingRequest() async throws {
        let engine = DelayedSemanticEngine()
        let session = session(engine: engine)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(10))
        let latest = "Now please verify our results"
        session.receiveTranscript(latest, segment: 2, endTime: 3.1)
        session.receiveTranscript(latest, segment: 2, endTime: 3.2)
        await session.semanticTask?.value
        let calls = await engine.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(session.activeWordRange, (body as NSString).range(of: "results"))
        session.hide()
    }

    func testNewAudioSegmentWithSameWordsStillCountsAsNewSpeech() async throws {
        let engine = DelayedSemanticEngine()
        let session = session(engine: engine)
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(10))
        session.receiveTranscript(spoken, segment: 4, endTime: 5)
        await session.semanticTask?.value
        let calls = await engine.calls
        XCTAssertEqual(calls, 2)
        session.hide()
    }

    func testCorrectionsAndNewUnrelatedWordsDiscardInFlightAnswer() async throws {
        for changed in ["Now let's verify our estimates", spoken + " unrelated holiday story abroad"] {
            let engine = DelayedSemanticEngine()
            let session = session(engine: engine)
            let old = session.activeWordRange
            session.receiveTranscript(spoken, segment: 2, endTime: 3)
            try await Task.sleep(for: .milliseconds(10))
            session.receiveTranscript(changed, segment: 2, endTime: 3.1)
            await session.semanticTask?.value
            XCTAssertEqual(session.activeWordRange, old)
            session.hide()
        }
    }

    func testDuplicatesDoNotExtendResultDeadline() async throws {
        let engine = DelayedSemanticEngine(delay: .milliseconds(300))
        let session = session(engine: engine)
        let old = session.activeWordRange
        session.receiveTranscript(spoken, segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(100))
        session.receiveTranscript(spoken, segment: 2, endTime: 3.1)
        await session.semanticTask?.value
        XCTAssertEqual(session.activeWordRange, old)
        let calls = await engine.calls
        XCTAssertEqual(calls, 1)
        session.hide()
    }

}
