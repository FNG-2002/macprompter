import AVFoundation
import NaturalLanguage
import Speech
import Observation

@MainActor @Observable
final class SpeechService {
    var status = "Bereit für deine Stimme"
    var level: Float = 0
    var isListening = false
    var onTranscript: ((String, Double, Double, SpeechResultTiming) -> Void)?
    var onFailure: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var converter: MicrophoneConverter?
    private var capture: AudioSinkCapture?
    private var sinkNode: AVAudioSinkNode?
    private var wordTracker = WordAppearanceTracker()
    private var generation = UUID()
    private(set) var audioSeconds: Double = 0
    private var audioClock = SpeechAudioClock()
    @ObservationIgnored private var meter = InputMeter()
    /// Diagnostics of the last start, shown in settings; never audio content.
    @ObservationIgnored private(set) var startMilliseconds: Double?
    /// The part of the start spent opening and starting the input device.
    @ObservationIgnored private(set) var startMicrophoneMilliseconds: Double?
    @ObservationIgnored private(set) var audioBlockMilliseconds: Double?
    @ObservationIgnored private(set) var recognizerTitle: String?
    /// Requested tap size for the fallback path. Taps deliver ~100 ms blocks
    /// in practice; the sink node path runs at the device I/O size instead.
    nonisolated static let blockSeconds = 0.01

    /// `dictation` uses Apple's dictation model with the script's words as
    /// vocabulary: new words about every 0.25 s instead of every ~0.95 s
    /// (measured 28 October 2026), and names from the script (ADR-20).
    func start(language: SpeechLanguage, vocabulary: [String] = [], dictation: Bool = false) async throws {
        stop()
        let run = generation
        let began = ProcessInfo.processInfo.systemUptime
        status = "Mikrofon vorbereiten …"
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechFailure("Mikrofonzugriff fehlt. Erlaube macprompter unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon.")
        }
        try check(run)
        var available = await Recognizer.make(language: language, dictation: dictation)
        // Without a dictation model for this language, the speech transcriber still works.
        if available == nil && dictation { available = await Recognizer.make(language: language, dictation: false) }
        guard let recognizer = available else {
            throw SpeechFailure("Die lokale Spracherkennung ist für diese Sprache auf diesem Mac nicht verfügbar. Nutze den automatischen oder manuellen Modus.")
        }
        try check(run)
        status = "Sprachmodell prüfen …"
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [recognizer.module]) {
            try check(run)
            status = "Sprachmodell laden · einmalig Internet nötig"
            try await request.downloadAndInstall()
        }
        try check(run)
        var microphone = ProcessInfo.processInfo.systemUptime
        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        microphone = ProcessInfo.processInfo.systemUptime - microphone
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [recognizer.module], considering: hardwareFormat) else {
            throw SpeechFailure("Kein geeignetes Mikrofon gefunden. Prüfe den Toneingang in den Systemeinstellungen.")
        }
        try check(run)
        let analysis = SpeechAnalyzer(modules: [recognizer.module])
        try await analysis.prepareToAnalyze(in: format)
        try await recognizer.prepare(analysis, vocabulary: vocabulary)
        try check(run)
        let (stream, sink) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(32))
        continuation = sink
        analyzer = analysis
        engine = audioEngine
        audioSeconds = 0
        audioClock = SpeechAudioClock()
        meter = InputMeter()
        wordTracker = WordAppearanceTracker()
        recognizerTitle = recognizer.title
        let attaching = ProcessInfo.processInfo.systemUptime
        try attachInput(to: audioEngine, format: format, sink: sink, run: run, startingAt: 0)
        resultsTask = Task { [weak self] in
            do {
                for try await result in recognizer.results() {
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.deliver(result)
                }
            } catch {
                guard let self, self.generation == run, !Task.isCancelled else { return }
                self.fail(error)
            }
        }
        analysisTask = Task { [weak self] in
            do { try await analysis.start(inputSequence: stream) }
            catch {
                guard let self, self.generation == run, !Task.isCancelled else { return }
                self.fail(error)
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                self.switchInput(format: format, sink: sink, run: run)
            }
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch where sinkNode != nil {
            // Some devices may refuse a sink node; the tap path still works.
            detachInput(from: audioEngine)
            try attachInput(to: audioEngine, format: format, sink: sink, run: run, startingAt: 0, preferSink: false)
            audioEngine.prepare()
            try audioEngine.start()
        }
        isListening = true
        startMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
        startMicrophoneMilliseconds = (microphone + ProcessInfo.processInfo.systemUptime - attaching) * 1000
        status = "Hört zu · \(language.title) · lokal"
    }

    private func attachInput(to engine: AVAudioEngine, format: AVAudioFormat, sink: AsyncStream<AnalyzerInput>.Continuation, run: UUID, startingAt frames: Int64, preferSink: Bool = true) throws {
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw SpeechFailure("Kein geeignetes Mikrofon gefunden. Prüfe den Toneingang in den Systemeinstellungen.")
        }
        // The sink node copies the first channel; it needs non-interleaved floats.
        let useSink = preferSink && hardwareFormat.commonFormat == .pcmFormatFloat32 && !hardwareFormat.isInterleaved
        let sourceFormat = useSink ? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardwareFormat.sampleRate, channels: 1, interleaved: false) ?? hardwareFormat : hardwareFormat
        let converter = try MicrophoneConverter(from: sourceFormat, to: format, startingAt: frames)
        self.converter = converter
        let tap = MicrophoneTap.make(converter: converter, sink: sink, onMetrics: { [weak self] amplitude, endTime in
            let deliveredAt = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                let reading = self.meter.observe(amplitude: amplitude, endTime: endTime)
                if let level = reading.level { self.level = level }
                self.audioBlockMilliseconds = reading.blockMilliseconds
                self.audioSeconds = endTime
                self.audioClock.observe(audioEnd: endTime, deliveredAt: deliveredAt)
            }
        }, onFailure: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                self.fail(error)
            }
        })
        if useSink, let capture = AudioSinkCapture(sampleRate: hardwareFormat.sampleRate, deliver: { buffer in
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: buffer.format.sampleRate))
        }) {
            let node = AVAudioSinkNode(receiverBlock: AudioSinkCapture.receiver(for: capture))
            engine.attach(node)
            engine.connect(input, to: node, format: hardwareFormat)
            self.capture = capture; sinkNode = node
        } else {
            let blockFrames = AVAudioFrameCount((hardwareFormat.sampleRate * Self.blockSeconds).rounded())
            input.installTap(onBus: 0, bufferSize: blockFrames, format: hardwareFormat, block: tap)
        }
    }

    private func detachInput(from engine: AVAudioEngine) {
        engine.inputNode.removeTap(onBus: 0)
        if let sinkNode { engine.disconnectNodeInput(sinkNode); engine.detach(sinkNode) }
        capture?.stop()
        capture = nil; sinkNode = nil
    }

    private func deliver(_ result: RecognizedText) {
        let now = ProcessInfo.processInfo.systemUptime
        var timing = SpeechResultTiming(receivedUptime: now, estimatedAudioEndUptime: audioClock.uptime(for: result.end))
        if result.isFinal {
            let words = Self.timedWords(in: result.text).map { ($0.word, $0.end.flatMap(audioClock.uptime(for:))) }
            (timing.wordLatencies, timing.wordsOnlyInFinal) = wordTracker.final(words, at: now)
        } else {
            let words = ScriptParser.words(in: String(result.text.characters)).map(\.normalized)
            timing.newWordGap = wordTracker.volatile(words, segment: result.start, at: now)
        }
        onTranscript?(String(result.text.characters), result.start, result.end, timing)
    }

    /// Contextual strings cost ~5.5 ms each on every start and do not affect
    /// speech already in progress (measured 28 October 2026). Only words the
    /// model would otherwise miss need them: words outside Apple's on-device
    /// word embedding vocabulary (~50,000 common words), or with digits or
    /// inner capitals. The spell checker is unsuitable: it accepts names and
    /// every word the user taught it.
    static func dictationVocabulary(for script: String, language: SpeechLanguage, limit: Int = 50) -> [String] {
        let embedding = NLEmbedding.wordEmbedding(for: language == .german ? .german : .english)
        return Array(ScriptParser.vocabulary(in: script).filter { word in
            word.contains(where: \.isNumber) || word.dropFirst().contains(where: \.isUppercase)
                || embedding.map { !$0.contains(word.lowercased()) && !$0.contains(word) } ?? true
        }.prefix(limit))
    }

    /// Final results time every word (volatile ones only their whole text).
    /// A run with several words times only its last one.
    nonisolated static func timedWords(in text: AttributedString) -> [(word: String, end: Double?)] {
        text.runs.flatMap { run -> [(word: String, end: Double?)] in
            let words = ScriptParser.words(in: String(text[run.range].characters)).map(\.normalized)
            return words.enumerated().map { index, word in (word, index == words.count - 1 ? run.audioTimeRange?.end.seconds : nil) }
        }
    }

    /// Headphones or AirPods connecting mid-take change the input format and
    /// stop the engine. The analyzer keeps running: the new input continues
    /// the same audio timeline, so pause/hover cut-offs stay valid.
    private func switchInput(format: AVAudioFormat, sink: AsyncStream<AnalyzerInput>.Continuation, run: UUID) {
        guard let engine else { return }
        engine.stop()
        detachInput(from: engine)
        do {
            try attachInput(to: engine, format: format, sink: sink, run: run, startingAt: converter?.frames ?? 0)
            // The pause while switching is not recognition latency.
            audioClock = SpeechAudioClock()
            engine.prepare()
            try engine.start()
        } catch {
            fail(SpeechFailure("Der neue Mikrofoneingang konnte nicht übernommen werden. Starte die Sprachsteuerung erneut."))
        }
    }

    private func check(_ run: UUID) throws {
        try Task.checkCancellation()
        if run != generation { throw CancellationError() }
    }

    private func fail(_ error: Error) {
        stop()
        status = error.localizedDescription
        onFailure?(error.localizedDescription)
    }

    func stop() {
        generation = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        if let engine { detachInput(from: engine) }
        engine = nil; converter = nil
        continuation?.finish(); continuation = nil
        resultsTask?.cancel(); resultsTask = nil
        analysisTask?.cancel(); analysisTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        isListening = false; level = 0
        status = "Mikrofon aus"
    }
}

/// The overlay meter needs ~30 Hz, not one SwiftUI update per 10 ms block;
/// it shows the peak since the last update so short syllables still register.
struct InputMeter {
    static let interval = 1.0 / 30
    private var pending: Float = 0
    private var publishedAt: Double?
    private var lastEnd: Double?

    mutating func observe(amplitude: Float, endTime: Double) -> (level: Float?, blockMilliseconds: Double?) {
        let block = lastEnd.map { (endTime - $0) * 1000 } ?? endTime * 1000
        lastEnd = endTime
        pending = max(pending, amplitude)
        guard publishedAt.map({ endTime - $0 >= Self.interval }) ?? true else { return (nil, block) }
        defer { pending = 0; publishedAt = endTime }
        return (pending, block)
    }
}

/// Text, audio range and finality, the same for both recognizers.
struct RecognizedText: Sendable {
    let text: AttributedString
    let start: Double
    let end: Double
    let isFinal: Bool
}

/// `SpeechTranscriber` with fast results (default) or `DictationTranscriber`
/// with the script's words as contextual strings (ADR-20). Shared by the app
/// and the speech integration tests.
enum Recognizer: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    static func make(language: SpeechLanguage, dictation: Bool) async -> Recognizer? {
        let wanted = Locale(identifier: language.rawValue)
        if dictation {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: wanted) else { return nil }
            return .dictation(DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange]))
        }
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { return nil }
        return .speech(SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange]))
    }

    var module: any SpeechModule {
        switch self { case .speech(let module): module; case .dictation(let module): module }
    }

    var title: String {
        switch self { case .speech: "Standard"; case .dictation: "Diktat mit Skriptvokabular" }
    }

    /// `SpeechTranscriber` ignores contextual strings; dictation uses them.
    func prepare(_ analyzer: SpeechAnalyzer, vocabulary: [String]) async throws {
        guard case .dictation = self, !vocabulary.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary
        try await analyzer.setContext(context)
    }

    func results() -> AsyncThrowingStream<RecognizedText, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch self {
                    case .speech(let module):
                        for try await r in module.results {
                            continuation.yield(RecognizedText(text: r.text, start: r.range.start.seconds, end: r.range.end.seconds, isFinal: r.isFinal))
                        }
                    case .dictation(let module):
                        for try await r in module.results {
                            continuation.yield(RecognizedText(text: r.text, start: r.range.start.seconds, end: r.range.end.seconds, isFinal: r.isFinal))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct SpeechFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Confined to AVAudioEngine's serial tap callback. Each yielded buffer is owned
/// by the analyzer; the engine's reusable input buffer never crosses threads.
final class MicrophoneConverter: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    /// Read on the main actor only after the tap was removed.
    private(set) var frames: Int64

    init(from: AVAudioFormat, to: AVAudioFormat, startingAt frames: Int64 = 0) throws {
        guard to.commonFormat == .pcmFormatInt16 else { throw SpeechFailure("Das Sprachmodell benötigt ein 16-Bit-Audioformat.") }
        guard let converter = AVAudioConverter(from: from, to: to) else { throw SpeechFailure("Audioformat konnte nicht konvertiert werden.") }
        self.converter = converter; format = to; self.frames = frames
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> ConvertedAudio {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw SpeechFailure("Audiopuffer konnte nicht angelegt werden.") }
        let feed = AudioInputFeed(input)
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if feed.supplied { status.pointee = .noDataNow; return nil }
            feed.supplied = true; status.pointee = .haveData; return feed.buffer
        }
        if let error { throw error }
        guard result != .error else { throw SpeechFailure("Audiokonvertierung fehlgeschlagen.") }
        var rms: Float = 0
        if let samples = input.floatChannelData?[0], input.frameLength > 0 {
            for i in 0..<Int(input.frameLength) { rms += samples[i] * samples[i] }
            rms = min(1, sqrt(rms / Float(input.frameLength)) * 8)
        }
        let time = CMTime(value: frames, timescale: CMTimeScale(format.sampleRate))
        frames += Int64(output.frameLength)
        return ConvertedAudio(buffer: output, level: rms, startTime: time)
    }
}

/// AVAudioConverter invokes its input block synchronously within convert().
private final class AudioInputFeed: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

struct ConvertedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let level: Float
    let startTime: CMTime
    var endTime: Double { startTime.seconds + Double(buffer.frameLength) / buffer.format.sampleRate }
    var analyzerInput: AnalyzerInput? {
        buffer.frameLength > 0 ? AnalyzerInput(buffer: buffer, bufferStartTime: startTime) : nil
    }
}

/// Created outside MainActor isolation: AVAudioEngine calls this on its audio
/// queue. Only Sendable callbacks may cross back to the UI; no actor check is
/// allowed at the tap entry point, even when created by SpeechService.start.
enum MicrophoneTap {
    nonisolated static func make(
        converter: MicrophoneConverter,
        sink: AsyncStream<AnalyzerInput>.Continuation,
        onMetrics: @escaping @Sendable (Float, Double) -> Void,
        onFailure: @escaping @Sendable (any Error) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            do {
                let chunk = try converter.convert(buffer)
                let amplitude = chunk.level
                let endTime = chunk.endTime
                if let input = chunk.analyzerInput { sink.yield(input) }
                onMetrics(amplitude, endTime)
            } catch { onFailure(error) }
        }
    }
}
