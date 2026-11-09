import XCTest
import Speech
import AVFoundation
@testable import MacPrompter

@MainActor
final class SpeechIntegrationTests: XCTestCase {
    func testGermanOnDeviceStreaming() async throws {
        let transcript = try await recognize(language: .german, fixture: "de")
        XCTAssertTrue(ScriptParser.normalize(transcript).contains("gute geschichten"), transcript)
    }
    func testEnglishOnDeviceStreaming() async throws {
        let transcript = try await recognize(language: .english, fixture: "en")
        XCTAssertTrue(transcript.lowercased().contains("simple idea"), transcript)
    }

    func testGermanRealTimeAsideAndResume() async throws {
        try await followInRealTime(language: .german, fixture: "de-aside",
            script: "Heute untersuchen wir Solarmodule und moderne Speicher liefern nachhaltige Energie. Anschließend betrachten wir die Kosten.",
            expectedWord: "Energie")
    }

    func testEnglishRealTimeAsideAndResume() async throws {
        try await followInRealTime(language: .english, fixture: "en-aside",
            script: "Welcome everyone. The batteries store clean energy for tomorrow. Next we discuss the investment.",
            expectedWord: "tomorrow")
    }

    func testGermanRealTimeWithDictationAndScriptVocabulary() async throws {
        try await followInRealTime(language: .german, fixture: "de-aside",
            script: "Heute untersuchen wir Solarmodule und moderne Speicher liefern nachhaltige Energie. Anschließend betrachten wir die Kosten.",
            expectedWord: "Energie", dictation: true)
    }

    func testEnglishRealTimeWithDictationAndScriptVocabulary() async throws {
        try await followInRealTime(language: .english, fixture: "en-aside",
            script: "Welcome everyone. The batteries store clean energy for tomorrow. Next we discuss the investment.",
            expectedWord: "tomorrow", dictation: true)
    }

    /// Paced PCM input exercises partial-result segmentation during real time,
    /// unlike the faster-than-real-time transcription tests below. Timing uses
    /// Speech's reported audio end; it is not hand-labelled word-end latency.
    private func followInRealTime(language: SpeechLanguage, fixture: String, script: String, expectedWord: String, dictation: Bool = false) async throws {
        guard let recognizer = await Recognizer.make(language: language, dictation: dictation) else {
            throw XCTSkip("Lokales Sprachmodell auf dieser Hardware nicht verfügbar")
        }
        let module = recognizer.module
        guard try await AssetInventory.assetInstallationRequest(supporting: [module]) == nil else {
            throw XCTSkip("Sprachmodell zuerst in macprompter installieren")
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture, withExtension: "aiff"))
        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
        let maybeFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: file.processingFormat)
        let format = try XCTUnwrap(maybeFormat)
        let converter = try MicrophoneConverter(from: file.processingFormat, to: format)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        try await recognizer.prepare(analyzer, vocabulary: SpeechService.dictationVocabulary(for: script, language: language))
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        session.script = Script(title: "Test", body: script, language: language)
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        let start = ProcessInfo.processInfo.systemUptime
        let expectedRange = (script as NSString).range(of: expectedWord)
        var sawExpectedDuringStream = false
        var inputFinished = false
        var resumeResultCount = 0
        var resumeCounts: [Int] = []
        var words = WordAppearanceTracker()
        var wordLatencies: [Double] = [], newWordGaps: [Double] = []
        let results = Task {
            for try await result in recognizer.results() {
                let now = ProcessInfo.processInfo.systemUptime
                if result.isFinal {
                    wordLatencies += words.final(SpeechService.timedWords(in: result.text).map { ($0.word, $0.end.map { start + $0 }) }, at: now).latencies
                } else if let gap = words.volatile(ScriptParser.words(in: String(result.text.characters)).map(\.normalized), segment: result.start, at: now) {
                    newWordGaps.append(gap)
                }
                let timing = SpeechResultTiming(receivedUptime: now, estimatedAudioEndUptime: start + result.end)
                session.receiveTranscript(String(result.text.characters), segment: result.start,
                    endTime: result.end, timing: timing)
                if session.activeWordRange == expectedRange && !inputFinished { sawExpectedDuringStream = true }
                if session.isOffScript { resumeResultCount += 1 }
                else if resumeResultCount > 0 { resumeCounts.append(resumeResultCount); resumeResultCount = 0 }
            }
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analysis = Task { try await analyzer.start(inputSequence: stream) }
        defer {
            results.cancel(); analysis.cancel(); continuation.finish(); session.hide()
            Task { await analyzer.cancelAndFinishNow() }
        }
        while file.framePosition < file.length {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048))
            try file.read(into: buffer)
            let converted = try converter.convert(buffer)
            let wait = start + converted.endTime - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            if let input = converted.analyzerInput { continuation.yield(input) }
        }
        // Deliver a little silence as live input: return evidence must not
        // depend on finalizing the analyzer when recording stops.
        for _ in 0..<10 {
            let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate / 10)))
            silence.frameLength = silence.frameCapacity
            if let channels = silence.floatChannelData {
                for c in 0..<Int(silence.format.channelCount) {
                    channels[c].initialize(repeating: 0, count: Int(silence.frameLength))
                }
            }
            let converted = try converter.convert(silence)
            let wait = start + converted.endTime - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            if let input = converted.analyzerInput { continuation.yield(input) }
        }
        inputFinished = true
        continuation.finish()
        try await analysis.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await results.value
        await analyzer.cancelAndFinishNow()
        XCTAssertEqual(session.activeWordRange, expectedRange)
        XCTAssertTrue(sawExpectedDuringStream, "Following must resume before the audio stream is finalized")
        let samples = session.speechLatency.samples
        let delays = samples.filter { !$0.revised }.compactMap(\.recognitionMilliseconds).sorted()
        let tracker = samples.map(\.trackerMilliseconds).sorted()
        XCTAssertFalse(delays.isEmpty)
        if !delays.isEmpty {
            let latency = SpeechLatencySummary([], words: wordLatencies, newWordGaps: newWordGaps)
            print("WORD_LATENCY \(recognizer.title) \(language.rawValue) words=\(wordLatencies.count) median_ms=\(Int(latency.word?.median ?? -1)) p95_ms=\(Int(latency.word?.p95 ?? -1)) new_words_every_ms=\(Int(latency.newWords?.median ?? -1))")
            print("PACED_SPEECH \(language.rawValue) samples=\(delays.count) estimated_ASR_p50_ms=\(delays[delays.count / 2]) estimated_ASR_p95_ms=\(delays[Int(Double(delays.count - 1) * 0.95)]) tracker_p95_ms=\(tracker[Int(Double(tracker.count - 1) * 0.95)]) recovered=\(!resumeCounts.isEmpty)")
        }
    }
    private func recognize(language: SpeechLanguage, fixture: String) async throws -> String {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else {
            throw XCTSkip("Lokales Sprachmodell auf dieser Hardware nicht verfügbar")
        }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            // Integration tests do not silently download large assets on a new machine.
            _ = installation
            throw XCTSkip("Sprachmodell zuerst in macprompter installieren")
        }
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: fixture, withExtension: "aiff"))
        let file = try AVAudioFile(forReading: url)
        let maybeFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: file.processingFormat)
        let format = try XCTUnwrap(maybeFormat)
        let converter = try MicrophoneConverter(from: file.processingFormat, to: format)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        let finished = expectation(description: "On-device transcription completed")
        var finalText = ""
        var resultError: Error?
        let results = Task {
            do {
                for try await result in module.results {
                    if result.isFinal { finalText += String(result.text.characters) + " " }
                }
            } catch { resultError = error }
            finished.fulfill()
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        while file.framePosition < file.length {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048))
            try file.read(into: buffer)
            if let input = try converter.convert(buffer).analyzerInput { continuation.yield(input) }
        }
        continuation.finish()
        try await analyzer.start(inputSequence: stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await fulfillment(of: [finished], timeout: 30)
        results.cancel()
        await analyzer.cancelAndFinishNow()
        if let resultError { throw resultError }
        print("LOCAL_SPEECH_\(language.rawValue): \(finalText)")
        return finalText
    }
}
