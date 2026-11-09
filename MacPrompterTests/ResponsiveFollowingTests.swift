import XCTest
import NaturalLanguage
import Speech
import CoreMedia
import AppKit
@testable import MacPrompter

final class ResponsiveFollowingTests: XCTestCase {
    func testDistinctiveNextWordResumesImmediatelyAfterLongAside() {
        var follower = ScriptFollower(text: "Heute untersuchen wir Solarmodule und moderne Speicher.")
        _ = follower.consume("Heute untersuchen wir", segment: 0, accepting: true)
        _ = follower.consume("Das erinnert mich an eine ziemlich lange Geschichte aus meinem letzten Urlaub mit Freunden", segment: 1, accepting: true)
        XCTAssertEqual(follower.nextIndex, 3)
        XCTAssertNotNil(follower.consume("Solarmodule", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testCommonNextWordWaitsOnlyUntilDistinctiveLocalContinuation() {
        var follower = ScriptFollower(text: "Welcome friends. The batteries store energy for tomorrow.")
        _ = follower.consume("Welcome friends", segment: 0, accepting: true)
        _ = follower.consume("Let me tell a completely unrelated story", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("the", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
        XCTAssertNotNil(follower.consume("the batteries", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testInsertedClausesDoNotRequireFourWordsToContinue() {
        for (script, prefix, aside, resume, expected) in [
            ("Wir zeigen die wichtigsten Ergebnisse unserer Untersuchung", "Wir zeigen", "und das hat mich gestern wirklich sehr uberrascht", "die wichtigsten", 4),
            ("Today we discuss the remarkable results of our experiment", "Today we discuss", "which was actually quite a surprise when I first saw it", "the remarkable", 5)
        ] {
            var follower = ScriptFollower(text: script)
            _ = follower.consume(prefix, segment: 0, accepting: true)
            _ = follower.consume(prefix + " " + aside, segment: 0, accepting: true)
            XCTAssertNotNil(follower.consume(prefix + " " + aside + " " + resume, segment: 0, accepting: true), script)
            XCTAssertEqual(follower.nextIndex, expected, script)
        }
    }

    func testFillerClusterBetweenTwoConfirmedWords() {
        var follower = ScriptFollower(text: "Wir entdecken nachhaltige Energie für alle")
        _ = follower.consume("Wir entdecken", segment: 0, accepting: true)
        _ = follower.consume("Wir entdecken äh also ähm naja", segment: 0, accepting: true)
        XCTAssertNotNil(follower.consume("Wir entdecken äh also ähm naja nachhaltige", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
    }

    func testFillersInsideLocalReturnAndAtEndOfBatch() {
        var follower = ScriptFollower(text: "Welcome everyone. The batteries store energy.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("Let us answer that unexpected question first", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("the um batteries uh", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testFillerWordsThatBelongToScriptRemainReadable() {
        var follower = ScriptFollower(text: "Also eigentlich ist genau dieser Punkt entscheidend")
        for (i, word) in ["Also", "eigentlich", "ist", "genau", "dieser", "Punkt", "entscheidend"].enumerated() {
            XCTAssertNotNil(follower.consume(word, segment: Double(i), accepting: true))
            XCTAssertEqual(follower.nextIndex, i + 1)
        }
    }

    func testPauseAndNewSegmentDoNotLoseAnchor() {
        var follower = ScriptFollower(text: "We discuss the future of sustainable energy")
        _ = follower.consume("We discuss", segment: 0, accepting: true)
        XCTAssertNotNil(follower.consume("the", segment: 120, accepting: true))
        XCTAssertEqual(follower.nextIndex, 3)
    }

    func testLocalReturnEvidenceSurvivesOneWordSegments() {
        var follower = ScriptFollower(text: "Welcome everyone. The batteries store energy.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("Let us answer another question first", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("the", segment: 2, accepting: true))
        XCTAssertNotNil(follower.consume("batteries", segment: 3, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    func testAnecdoteWithUnconnectedNearbyWordsDoesNotAdvance() {
        var follower = ScriptFollower(text: "Welcome everyone. The batteries store energy for our building.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        for (i, phrase) in ["I had forgotten the", "restaurant batteries were empty", "we visited a store yesterday", "and later had no energy left"].enumerated() {
            XCTAssertNil(follower.consume(phrase, segment: Double(i + 1), accepting: true))
            XCTAssertEqual(follower.nextIndex, 2)
        }
    }

    func testCorrectedUncommittedWordDoesNotSupplyStaleEvidence() {
        var follower = ScriptFollower(text: "Welcome everyone. The batteries store energy.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("We should answer another audience question", segment: 1, accepting: true)
        _ = follower.consume("the", segment: 2, accepting: true)
        XCTAssertNil(follower.consume("some batteries", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testTwoWordLocalRecoveryCanSkipOneMisrecognizedWord() {
        var follower = ScriptFollower(text: "Welcome everyone. These remarkable batteries store clean energy.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("I have an unrelated story about my vacation", segment: 1, accepting: true)
        XCTAssertNotNil(follower.consume("those remarkable batteries", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 5)
    }

    func testDistantSingleDistinctiveWordStillCannotJump() {
        let middle = Array(repeating: "other topics", count: 60).joined(separator: " ")
        var follower = ScriptFollower(text: "Welcome everyone. \(middle) Solarmodule liefern nachhaltige Energie.")
        _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
        _ = follower.consume("Let us consider a different example today", segment: 1, accepting: true)
        XCTAssertNil(follower.consume("Solarmodule", segment: 2, accepting: true))
        XCTAssertEqual(follower.nextIndex, 2)
    }

    func testLongBatchOfCommonScriptWordsIsNotMistakenForAnAside() {
        var follower = ScriptFollower(text: "This is what we have here and this is what we have there today")
        XCTAssertNotNil(follower.consume("This is what we have here and this is what we have there", segment: 0, accepting: true))
        XCTAssertEqual(follower.nextIndex, 13)
    }

    func testFullEarlierPhraseOutweighsCoincidentalNextWord() {
        var follower = ScriptFollower(text: "Engineers design efficient batteries. These systems power hospitals. Batteries reduce our energy costs.")
        _ = follower.consume("Engineers design efficient batteries", segment: 0, accepting: true)
        _ = follower.consume("These systems power hospitals", segment: 1, accepting: true)
        _ = follower.consume("Let me repeat the earlier point again", segment: 2, accepting: true)
        XCTAssertNotNil(follower.consume("Engineers design efficient batteries", segment: 3, accepting: true))
        XCTAssertEqual(follower.nextIndex, 4)
    }

    // Held-out wording, unrelated to the energy examples used while developing.
    func testLocalReturnWithCookingAndTravelVocabulary() {
        for (script, prefix, aside, resumed, position) in [
            ("Jetzt schneiden wir die frischen Tomaten in kleine Würfel", "Jetzt schneiden wir", "das Messer habe ich übrigens von meiner Großmutter bekommen", "die frischen", 5),
            ("After lunch visit the botanical gardens near the station", "After lunch visit", "I remember getting completely lost there on my first visit", "the botanical", 5)
        ] {
            var follower = ScriptFollower(text: script)
            _ = follower.consume(prefix, segment: 0, accepting: true)
            _ = follower.consume(aside, segment: 1, accepting: true)
            XCTAssertNotNil(follower.consume(resumed, segment: 2, accepting: true))
            XCTAssertEqual(follower.nextIndex, position)
        }
    }

    func testTrackerLatencyOnLongScript() {
        let text = (0..<200).map { "Abschnitt \($0) behandelt Solarmodule und moderne Speicher für unsere gemeinsame Zukunft." }.joined(separator: " ")
        var durations: [Double] = []
        for _ in 0..<10 {
            var follower = ScriptFollower(text: text)
            for (i, phrase) in ["Abschnitt", "Abschnitt null", "Abschnitt null behandelt Solarmodule", "Das erinnert mich an eine Geschichte aus dem Urlaub", "und moderne", "Speicher", "für unsere gemeinsame Zukunft", "unrelated question", "Zukunft"].enumerated() {
                let start = ProcessInfo.processInfo.systemUptime
                _ = follower.consume(phrase, segment: Double(i), accepting: true)
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
        }
        durations.sort()
        let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
        print("TRACKER_BENCHMARK words=\(ScriptParser.words(in: text).count) samples=\(durations.count) p50_ms=\(durations[durations.count / 2]) p95_ms=\(p95) max_ms=\(durations.last!)")
        // A loose regression guard also works on shared/slower CI machines.
        XCTAssertLessThan(p95, 100)
    }
}

@MainActor
final class SpeechLatencyTests: XCTestCase {
    func testAudioClockMapsAudioTimeWithoutMainQueueDelay() {
        var clock = SpeechAudioClock()
        XCTAssertNil(clock.uptime(for: 1))
        clock.observe(audioEnd: 1, deliveredAt: 101)
        clock.observe(audioEnd: 2, deliveredAt: 102.1)
        XCTAssertEqual(clock.uptime(for: 1.5)!, 101.5, accuracy: 0.001)
    }

    func testDiagnosticsAreBoundedAndKeepRecognitionSeparateFromHighlight() {
        var metrics = SpeechLatencyMetrics()
        for _ in 0..<300 {
            _ = metrics.record(timing: SpeechResultTiming(receivedUptime: 100, estimatedAudioEndUptime: 99.8),
                trackerSeconds: 0.001, revised: false, matched: false)
        }
        let id = metrics.record(timing: SpeechResultTiming(receivedUptime: 101, estimatedAudioEndUptime: 100.8),
            trackerSeconds: 0.002, revised: true, matched: true)
        metrics.appliedHighlight(sampleID: id, at: 101.016)
        metrics.appliedHighlight(sampleID: id, at: 102)
        XCTAssertEqual(metrics.samples.count, 256)
        XCTAssertEqual(metrics.samples.last!.recognitionMilliseconds!, 200, accuracy: 0.001)
        XCTAssertEqual(metrics.samples.last!.trackerMilliseconds, 2, accuracy: 0.001)
        XCTAssertEqual(metrics.samples.last!.highlightMilliseconds!, 16, accuracy: 0.001)
        XCTAssertTrue(metrics.samples.last!.revised)
    }

    func testDiagnosticSummaryReportsNearestRankPercentilesWithoutWords() {
        var metrics = SpeechLatencyMetrics()
        XCTAssertEqual(metrics.summary.events, 0)
        XCTAssertNil(metrics.summary.recognition)
        for i in 1...20 {
            let id = metrics.record(timing: SpeechResultTiming(receivedUptime: 100, estimatedAudioEndUptime: 100 - Double(i) * 0.06),
                trackerSeconds: 0.0001 * Double(i), revised: i % 5 == 0, matched: i % 2 == 0)
            if i % 2 == 0 { metrics.appliedHighlight(sampleID: id, at: 100.004) }
        }
        let summary = metrics.summary
        XCTAssertEqual(summary.events, 20)
        XCTAssertEqual(summary.advanced, 10)
        XCTAssertEqual(summary.revised, 4)
        XCTAssertEqual(summary.recognition!.median, 600, accuracy: 0.001)
        XCTAssertEqual(summary.recognition!.p95, 1140, accuracy: 0.001)
        XCTAssertEqual(summary.slowRecognitions, 4)
        XCTAssertEqual(summary.tracker!.p95, 1.9, accuracy: 0.001)
        XCTAssertEqual(summary.highlight!.median, 4, accuracy: 0.001)
    }

    func testTimedWordsComeFromFinalRunsAndTimeOnlyTheLastWordOfARun() {
        func run(_ text: String, _ start: Double, _ end: Double) -> AttributedString {
            var part = AttributedString(text)
            part.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000), end: CMTime(seconds: end, preferredTimescale: 1000))
            return part
        }
        let text = run("Moderne", 0, 0.4) + run(" ", 0.4, 0.45) + run("Speicher", 0.45, 0.9) + run(" liefern nachhaltige", 0.9, 1.6)
        let words = SpeechService.timedWords(in: text)
        XCTAssertEqual(words.map(\.word), ["moderne", "speicher", "liefern", "nachhaltige"])
        XCTAssertEqual(words.map(\.end), [0.4, 0.9, nil, 1.6])
    }

    func testWordLatencyComesFromFirstVolatileAppearanceAgainstFinalWordEnd() {
        var tracker = WordAppearanceTracker()
        XCTAssertNil(tracker.volatile(["wir"], segment: 0, at: 1.0))
        XCTAssertEqual(tracker.volatile(["wir", "planen"], segment: 0, at: 1.25)!, 250, accuracy: 0.001)
        XCTAssertNil(tracker.volatile(["wir", "planen"], segment: 0, at: 1.27), "same burst")
        XCTAssertEqual(tracker.volatile(["wir", "planen", "dry"], segment: 0, at: 2.0)!, 730, accuracy: 0.001)
        XCTAssertNil(tracker.volatile(["wir", "planen", "drei"], segment: 0, at: 4.5), "a pause is not the rhythm")
        let (latencies, unseen) = tracker.final([("wir", 0.4), ("planen", 0.7), ("drei", 1.1), ("und", nil), ("wir", 1.6)], at: 5.0)
        // "drei" first appeared correctly at 4.5; the second "wir" only in the final.
        XCTAssertEqual(latencies.count, 3)
        XCTAssertEqual(latencies[0], 600, accuracy: 0.001)
        XCTAssertEqual(latencies[1], 550, accuracy: 0.001)
        XCTAssertEqual(latencies[2], 3400, accuracy: 0.001)
        XCTAssertEqual(unseen, 1, "a word only the final shows is counted, not timed")
    }

    @MainActor
    func testDictationVocabularyKeepsOnlyUnusualWords() throws {
        guard NLEmbedding.wordEmbedding(for: .german) != nil else { throw XCTSkip("Wortmodell für Deutsch fehlt") }
        let words = SpeechService.dictationVocabulary(for: "Heute zeigt Tamsin Wieczorek den macprompter mit SpeechAnalyzer und 25 Prozent mehr Energie für unsere Kunden.", language: .german)
        for expected in ["Wieczorek", "macprompter", "SpeechAnalyzer", "Tamsin"] { XCTAssertTrue(words.contains(expected), expected) }
        for common in ["Heute", "Energie", "Kunden", "Prozent", "unsere"] { XCTAssertFalse(words.contains(common), common) }
        XCTAssertLessThanOrEqual(SpeechService.dictationVocabulary(for: (0..<200).map { "Zqx\($0)wort" }.joined(separator: " "), language: .german).count, 50)
    }

    func testVocabularyKeepsWrittenFormLongestFirstWithoutCues() {
        let words = ScriptParser.vocabulary(in: "Heute zeigt Tamsin Wieczorek den macprompter. [Pause] Tamsin zeigt es.", limit: 4)
        XCTAssertEqual(words, ["macprompter", "Wieczorek", "Tamsin", "Heute"])
    }

    func testDiagnosticsExplainEventsWithoutProgress() {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: "Moderne Speicher liefern nachhaltige Energie für morgen")
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.receiveTranscript("Moderne Speicher", segment: 0, endTime: 1)
        session.receiveTranscript("Moderne Speicher.", segment: 0, endTime: 1)
        session.receiveTranscript("Moderne", segment: 0, endTime: 1)
        session.receiveTranscript("Kaffee", segment: 1, endTime: 1.5)
        session.receiveTranscript("für", segment: 2, endTime: 2)
        session.receiveTranscript("Das erinnert mich an gestern", segment: 3, endTime: 3)
        session.setHover(true)
        session.receiveTranscript("liefern nachhaltige", segment: 4, endTime: 4)
        let outcomes = session.speechLatency.summary.outcomes
        XCTAssertEqual(outcomes[.advanced], 1)
        XCTAssertEqual(outcomes[.duplicate], 1)
        XCTAssertEqual(outcomes[.revision], 1)
        XCTAssertEqual(outcomes[.unknownWord], 1, "Kaffee is not in the script")
        XCTAssertEqual(outcomes[.ambiguous], 1, "a lone distant script word is not enough")
        XCTAssertEqual(outcomes[.offScript], 1)
        XCTAssertEqual(outcomes[.paused], 1)
    }

    func testWordLatencyAndRhythmAreSummarizedSeparately() {
        var metrics = SpeechLatencyMetrics()
        _ = metrics.record(timing: SpeechResultTiming(receivedUptime: 10, estimatedAudioEndUptime: 9.97, wordLatencies: [100, 400, 700]),
            trackerSeconds: 0, revised: false, matched: true)
        _ = metrics.record(timing: SpeechResultTiming(receivedUptime: 11, estimatedAudioEndUptime: 10.98, newWordGap: 250),
            trackerSeconds: 0, revised: false, matched: false)
        XCTAssertEqual(metrics.summary.word!.median, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.summary.word!.p95, 700, accuracy: 0.001)
        XCTAssertEqual(metrics.summary.newWords!.median, 250, accuracy: 0.001)
        XCTAssertEqual(metrics.summary.recognition!.p95, 30, accuracy: 0.001)
    }

    func testInputMeterPublishesPeakLevelAtThirtyHertzForTenMillisecondBlocks() {
        var meter = InputMeter()
        var published: [Float] = []
        var blocks: [Double] = []
        for i in 1...100 {
            let amplitude: Float = i == 15 ? 0.9 : 0.1
            let reading = meter.observe(amplitude: amplitude, endTime: Double(i) * SpeechService.blockSeconds)
            if let level = reading.level { published.append(level) }
            blocks.append(reading.blockMilliseconds!)
        }
        XCTAssertEqual(published.count, 25)
        XCTAssertEqual(published.filter { $0 == 0.9 }.count, 1, "a short peak between updates must not be lost")
        XCTAssertEqual(blocks.last!, 10, accuracy: 0.001)
    }

    func testBatchedSpeechHighlightsNewestWordWithoutTimerOrBacklog() throws {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: "Today we discuss clean energy and modern batteries together")
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
        view.update(preferences: preferences.value)
        view.layoutSubtreeIfNeeded()
        session.receiveTranscript("Today we discuss clean energy", segment: 0, endTime: 1)
        let expected = (session.script.body as NSString).range(of: "energy")
        XCTAssertEqual(session.activeWordRange, expected)
        view.update(preferences: preferences.value)
        let clip = try XCTUnwrap(view.subviews.first as? NSClipView)
        let text = try XCTUnwrap(clip.documentView as? NSTextView)
        XCTAssertNotNil(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: expected.location, effectiveRange: nil))
        let sample = try XCTUnwrap(session.speechLatency.samples.last)
        XCTAssertLessThan(try XCTUnwrap(sample.highlightMilliseconds), 50)
        print("HIGHLIGHT_APPLICATION_MS \(sample.highlightMilliseconds!)")
        session.receiveTranscript("Today we discuss clean energy and modern batteries", segment: 0, endTime: 2)
        XCTAssertEqual(session.activeWordRange, (session.script.body as NSString).range(of: "batteries"))
        session.setHover(true)
        session.receiveTranscript("Today we discuss clean energy and modern batteries together", segment: 0, endTime: 3)
        session.setHover(false)
        session.advanceReading(by: 0.1)
        XCTAssertEqual(session.activeWordRange, (session.script.body as NSString).range(of: "batteries"))
        session.hide()
    }
}
