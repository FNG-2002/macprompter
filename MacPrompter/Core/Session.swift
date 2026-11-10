import AppKit
import Observation

@MainActor @Observable
final class PrompterSession {
    let preferences: PreferenceStore
    let speech = SpeechService()
    var script = Script.welcome
    var gate = PlaybackGate()
    @ObservationIgnored var offset = 0.0 {
        didSet { if offset != oldValue { onOffsetChange?() } }
    }
    @ObservationIgnored var onOffsetChange: (() -> Void)?
    var maximumOffset = 0.0
    var targetCharacter: Int?
    var activeWordRange: NSRange?
    var isOffScript = false
    private(set) var voiceDestination: Double?
    /// Slide sync for scripts linked to a PDF; nil for plain scripts.
    private(set) var slideTimeline: SlideTimeline?
    private(set) var currentSlide: Int?
    /// A character the reader should jump to (manual slide navigation).
    private(set) var jumpCharacter: Int?
    @ObservationIgnored private var readingSlide: Int?
    @ObservationIgnored private var adoptReadingSlide = false
    private var lastRecognitionAge = 0.0
    @ObservationIgnored private var lead = ReadingLead()
    @ObservationIgnored private var voiceActivity = VoiceActivity()
    @ObservationIgnored private var voiceClock = 0.0
    /// Experimental highlight lead: the word shown ahead of the last
    /// recognized one; nil while the highlight is on a recognized word.
    @ObservationIgnored private(set) var predictedWordIndex: Int?
    static let predictedWordsAhead = 2
    /// Supplied by the reader: continuous scroll offset for a character
    /// position, used by speech-paced scrolling.
    @ObservationIgnored var voiceGeometry: ((Double) -> Double?)?
    private var reachedScriptEnd = false
    @ObservationIgnored var elapsed = 0.0
    private(set) var elapsedSeconds = 0
    var errorMessage: String?
    var isPreparing = false
    var onVisibilityChange: ((Bool) -> Void)?
    var onManualMovement: (() -> Void)?
    private var follower = ScriptFollower(text: "")
    private var startTask: Task<Void, Never>?
    private var countdownRemainder = 0.0
    private var ignoreSpeechThrough = 0.0
    @ObservationIgnored private(set) var speechLatency = SpeechLatencyMetrics()
    @ObservationIgnored private var pendingHighlightSample: (id: UInt64, range: NSRange)?
    private(set) var semanticGermanAvailable: Bool?
    private(set) var semanticEnglishAvailable: Bool?
    @ObservationIgnored private let semanticEngine: any SemanticRecovering
    @ObservationIgnored private(set) var semanticTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSemantic: SemanticRecoveryRequest?
    @ObservationIgnored private var semanticRevision: UInt64 = 0
    @ObservationIgnored private var semanticIndex = SemanticScriptIndex(text: "")
    @ObservationIgnored private var semanticWindows: [SemanticWindow] = []
    @ObservationIgnored private var semanticWindowAnchor: Int?
    @ObservationIgnored private(set) var lastSemanticMilliseconds: Double?
    /// Injectable so tests do not depend on the host's accessibility settings.
    @ObservationIgnored var systemReducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var progress: Double { maximumOffset > 0 ? min(1, offset / maximumOffset) : 0 }
    var stateLabel: String {
        if !gate.isVisible { return "Bereit für deinen nächsten Take" }
        if isPreparing { return speech.status }
        if gate.isHovering { return "Hover-Pause" }
        if gate.countdown > 0 { return "Start in \(gate.countdown)" }
        if !gate.isPlaying { return "Pausiert" }
        if preferences.value.mode == .voice && isOffScript { return "Hört zu · wartet auf deinen Skripttext" }
        return preferences.value.mode == .voice ? speech.status : (preferences.value.mode == .manual ? "Manuell · Pfeiltasten & Scrollrad" : "Läuft")
    }

    init(preferences: PreferenceStore, semanticEngine: any SemanticRecovering = AppleSemanticRecovery()) {
        self.preferences = preferences
        self.semanticEngine = semanticEngine
        speech.onTranscript = { [weak self] text, segment, endTime, timing in
            self?.receiveTranscript(text, segment: segment, endTime: endTime, timing: timing)
        }
        speech.onFailure = { [weak self] message in
            self?.gate.isPlaying = false
            self?.errorMessage = message
        }
    }

    func present(_ script: Script) {
        if self.script != script || !gate.isVisible {
            stopWork()
            self.script = script
            reset()
        }
        gate.isVisible = true
        warmSemanticRecovery()
        onVisibilityChange?(true)
    }

    func hide() {
        stopWork()
        gate.isVisible = false; gate.isHovering = false; gate.isPlaying = false; gate.countdown = 0
        onVisibilityChange?(false)
    }

    func togglePlayback() {
        guard gate.isVisible else { return }
        if gate.isPlaying || isPreparing { pause(); return }
        if reachedScriptEnd || (preferences.value.mode != .voice && progress >= 0.999) { reset() }
        errorMessage = nil
        gate.countdown = preferences.value.countdownSeconds
        countdownRemainder = Double(gate.countdown)
        if preferences.value.mode == .voice {
            isPreparing = true
            startTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.speech.start(language: self.script.language,
                        vocabulary: SpeechService.dictationVocabulary(for: self.script.body, language: self.script.language), dictation: true)
                    try Task.checkCancellation()
                    self.isPreparing = false
                    self.gate.isPlaying = true
                    self.ignoreSpeechThrough = self.speech.audioSeconds
                } catch is CancellationError { }
                catch {
                    guard !Task.isCancelled else { return }
                    self.speech.stop()
                    self.isPreparing = false; self.gate.isPlaying = false; self.gate.countdown = 0
                    self.errorMessage = error.localizedDescription
                }
            }
        } else { gate.isPlaying = true }
    }

    /// Only the clock; position, slides and playback stay as they are.
    func resetTimer() {
        elapsed = 0; elapsedSeconds = 0
    }

    func pause() {
        stopWork()
        gate.isPlaying = false; gate.countdown = 0
    }

    func reset() {
        invalidateSemanticRecovery()
        semanticWindows = []; semanticWindowAnchor = nil
        speechLatency = SpeechLatencyMetrics(); pendingHighlightSample = nil
        lead.reset(); voiceClock = 0; predictedWordIndex = nil
        offset = 0; elapsed = 0; elapsedSeconds = 0; activeWordRange = nil
        voiceDestination = nil; isOffScript = false
        reachedScriptEnd = false; lastRecognitionAge = 0
        follower = ScriptFollower(text: script.body)
        if semanticIndex.text != script.body { semanticIndex = SemanticScriptIndex(text: script.body, tokens: follower.tokens) }
        targetCharacter = follower.tokens.first?.range.location
        slideTimeline = script.presentation.map(PresentationComposer.compose).flatMap { $0.body == script.body ? $0.timeline : nil }
        currentSlide = slideTimeline?.page(at: 0)
        readingSlide = nil; adoptReadingSlide = false; jumpCharacter = nil
    }

    var slideStatus: SlideStatus? {
        guard let slideTimeline, let currentSlide else { return nil }
        return SlideStatus(current: currentSlide, count: slideTimeline.pageCount,
            position: slideTimeline.positions.indices.contains(currentSlide) ? slideTimeline.positions[currentSlide] : nil,
            slideCount: slideTimeline.slideCount)
    }

    /// Manual slide navigation (keys, clicker, remote). The slide always
    /// changes; the text only jumps when the gate allows movement.
    func stepSlide(_ delta: Int) {
        guard let slideTimeline, let currentSlide, slideTimeline.pageCount > 0 else { return }
        showSlide(min(slideTimeline.pageCount - 1, max(0, currentSlide + delta)))
    }

    func showSlide(_ page: Int) {
        guard let slideTimeline, slideTimeline.pageCount > page, page >= 0, page != currentSlide else { return }
        currentSlide = page
        guard gate.allowsMovement, let anchor = slideTimeline.anchor(forPage: page) else { return }
        invalidateSemanticRecovery()
        pendingHighlightSample = nil
        // Spoken words continue exactly at the anchor; only the scrolled focus
        // line can land a little before the chosen page's cue.
        adoptReadingSlide = preferences.value.mode != .voice
        voiceDestination = nil; targetCharacter = nil
        if preferences.value.mode == .voice {
            follower.seek(character: anchor)
            activeWordRange = nil; reachedScriptEnd = false; isOffScript = false
            ignoreSpeechThrough = speech.audioSeconds + 0.15
        }
        jumpCharacter = anchor
    }

    func resolveJump(_ value: Double, for character: Int) {
        guard jumpCharacter == character else { return }
        jumpCharacter = nil
        guard gate.allowsMovement else { return }
        offset = min(maximumOffset, max(0, value))
    }

    /// Reported by the reader for timer scrolling and, in every mode, for
    /// manual moves. Voice mode otherwise follows the spoken words.
    func readerReached(character: Int, manual: Bool = false) {
        guard manual || preferences.value.mode != .voice else { return }
        followReading(at: character)
    }

    private func followReading(at character: Int) {
        guard let page = slideTimeline?.page(at: character) else { return }
        defer { readingSlide = page }
        // Right after a manual jump the reading position only takes over the
        // chosen slide; it must not snap back to a neighbouring page.
        if adoptReadingSlide { adoptReadingSlide = false; return }
        // Off: slides change only by hand; the text still follows those changes.
        if preferences.value.slidesFollowReading, page != readingSlide && page != currentSlide { currentSlide = page }
    }

    func setHover(_ hovering: Bool) {
        invalidateSemanticRecovery()
        pendingHighlightSample = nil
        gate.isHovering = hovering
        targetCharacter = nil
        if hovering { voiceDestination = nil }
        lead.reset(); predictedWordIndex = nil
        // Drop both already delivered and late-arriving audio from the pause.
        ignoreSpeechThrough = speech.audioSeconds + (hovering ? 0 : 0.15)
    }

    func nudge(_ points: Double) {
        guard gate.allowsMovement else { return }
        move(by: points)
    }

    /// Mouse wheel or trackpad, on the prompter or anywhere else. Same
    /// direction as any macOS scroll view, so natural scrolling applies.
    func scrollWheel(deltaY: Double, precise: Bool) {
        guard gate.allowsScrolling, deltaY != 0 else { return }
        let p = preferences.value
        move(by: -deltaY * (precise ? 1 : p.fontSize + p.lineSpacing))
    }

    private func move(by points: Double) {
        invalidateSemanticRecovery()
        pendingHighlightSample = nil
        offset = min(maximumOffset, max(0, offset + points))
        targetCharacter = nil; voiceDestination = nil; activeWordRange = nil
        lead.reset(); predictedWordIndex = nil
        ignoreSpeechThrough = speech.audioSeconds + 0.15
        onManualMovement?()
    }

    func seekVoice(to character: Int) {
        invalidateSemanticRecovery()
        follower.seek(character: character)
        reachedScriptEnd = false; isOffScript = false
        lead.reset(); predictedWordIndex = nil
    }

    func receiveTranscript(_ text: String, segment: Double, endTime: Double, timing: SpeechResultTiming? = nil) {
        let start = ProcessInfo.processInfo.systemUptime
        let accepts = gate.allowsAutomaticMovement && endTime > ignoreSpeechThrough
        _ = follower.consume(text, segment: segment, accepting: accepts)
        // A final/volatile duplicate must not discard an in-flight answer or
        // replace its original deadline. New evidence and rejected audio do.
        if !accepts || !follower.lastInputWasDuplicate { invalidateSemanticRecovery() }
        let match = follower.lastMatch
        let outcome: SpeechEventOutcome = !accepts ? .paused : match != nil ? .advanced
            : follower.lastInputWasDuplicate ? .duplicate
            : !follower.hasFreshEvidence ? (follower.lastInputWasRevision ? .revision : .nothingNew)
            : follower.isOffScript ? .offScript : follower.lastWordInScript ? .ambiguous : .unknownWord
        let sampleID = speechLatency.record(timing: timing ?? SpeechResultTiming(receivedUptime: start),
            trackerSeconds: ProcessInfo.processInfo.systemUptime - start,
            revised: follower.lastInputWasRevision, matched: match != nil, outcome: outcome)
        guard let match else {
            if accepts { isOffScript = follower.isOffScript }
            if accepts, preferences.value.mode == .voice {
                queueSemanticRecovery(heard: follower.semanticEvidence())
            }
            return
        }
        isOffScript = false; lastRecognitionAge = 0
        reachedScriptEnd = follower.nextIndex == follower.tokens.count
        // Speech can deliver several words at once. Show the latest confirmed
        // word immediately; replaying old words only adds visible latency.
        if let last = match.wordIndices.last {
            showWord(last, jump: match.reacquired)
            if let range = activeWordRange { pendingHighlightSample = (sampleID, range) }
        }
    }

    func checkSemanticModels() async {
        semanticGermanAvailable = await semanticEngine.available(for: .german)
        semanticEnglishAvailable = await semanticEngine.available(for: .english)
    }

    private func invalidateSemanticRecovery() {
        semanticRevision &+= 1
        pendingSemantic = nil
        // Synchronous model work cannot be interrupted safely. Keep the one
        // worker alive; its revision check discards obsolete results.
    }

    private func warmSemanticRecovery() {
        guard gate.isVisible, preferences.value.mode == .voice else { return }
        queueSemanticRecovery(heard: [], warmUp: true)
    }

    private func queueSemanticRecovery(heard: [String], warmUp: Bool = false) {
        guard warmUp || heard.count >= 4 else { return }
        if semanticWindowAnchor != follower.nextIndex {
            semanticWindows = semanticIndex.windows(nextIndex: follower.nextIndex)
            semanticWindowAnchor = follower.nextIndex
        }
        guard !semanticWindows.isEmpty else { return }
        if !warmUp && !semanticWindows.contains(where: {
            SemanticCandidates.anchor(heard: heard, window: $0, allWindows: semanticWindows) != nil
        }) { return }
        pendingSemantic = SemanticRecoveryRequest(revision: semanticRevision, nextIndex: follower.nextIndex,
            language: script.language, heard: heard, windows: semanticWindows)
        guard semanticTask == nil else { return }
        // One in-flight evaluation + one replaceable latest request. Partial
        // results never create an unbounded inference queue.
        semanticTask = Task { [weak self] in
            while let self, let request = self.pendingSemantic {
                self.pendingSemantic = nil
                let result = await self.semanticEngine.evaluate(request)
                self.recordSemanticAvailability(result.available, language: request.language)
                self.lastSemanticMilliseconds = result.milliseconds
                guard self.semanticRevision == request.revision,
                      self.preferences.value.mode == .voice, self.gate.allowsAutomaticMovement,
                      !self.isPreparing, !request.heard.isEmpty,
                      ProcessInfo.processInfo.systemUptime - request.createdUptime < 0.25,
                      let index = result.wordIndex,
                      self.follower.acceptSemanticAnchor(index, expectedNextIndex: request.nextIndex) else { continue }
                self.isOffScript = false; self.lastRecognitionAge = 0
                self.reachedScriptEnd = self.follower.nextIndex == self.follower.tokens.count
                self.speechLatency.recordSemanticReturn()
                self.showWord(index, jump: true)
            }
            self?.semanticTask = nil
        }
    }

    private func recordSemanticAvailability(_ available: Bool, language: SpeechLanguage) {
        if language.code == "de" { semanticGermanAvailable = available }
        else if language.code == "en" { semanticEnglishAvailable = available }
    }

    func didApplyWordHighlight(_ range: NSRange?) {
        guard let pending = pendingHighlightSample, pending.range == range else { return }
        speechLatency.appliedHighlight(sampleID: pending.id, at: ProcessInfo.processInfo.systemUptime)
        pendingHighlightSample = nil
    }

    private func showWord(_ index: Int, jump: Bool) {
        guard follower.tokens.indices.contains(index) else { return }
        // A predicted highlight ahead of the recognized word stays: moving
        // back to a word already passed looks like a stutter.
        if !jump, let predicted = predictedWordIndex, predicted > index {
            // keep the highlight where it is
        } else {
            predictedWordIndex = nil
            activeWordRange = follower.tokens[index].range
            targetCharacter = index + 1 < follower.tokens.count
                ? follower.tokens[index + 1].range.location : follower.tokens[index].range.location
        }
        lead.confirm(character: Double(index + 1 < follower.tokens.count ? follower.tokens[index + 1].range.location : NSMaxRange(follower.tokens[index].range)),
                     at: voiceClock, jump: jump)
        // The slide switches once the last word of its section was spoken.
        if slideTimeline != nil {
            followReading(at: index + 1 < follower.tokens.count ? follower.tokens[index + 1].range.location : NSMaxRange(follower.tokens[index].range))
        }
    }

    func resolveVoiceDestination(_ value: Double, for character: Int) {
        guard targetCharacter == character, !gate.isHovering else { return }
        targetCharacter = nil
        voiceDestination = min(maximumOffset, max(0, value))
    }


    func refreshVoiceLayout() {
        guard preferences.value.mode == .voice, !gate.isHovering, activeWordRange != nil else { return }
        let index = min(follower.nextIndex, follower.tokens.count - 1)
        if follower.tokens.indices.contains(index) { targetCharacter = follower.tokens[index].range.location }
    }

    private func stopWork() {
        invalidateSemanticRecovery()
        pendingHighlightSample = nil
        startTask?.cancel(); startTask = nil
        speech.stop(); isPreparing = false
        voiceDestination = nil; targetCharacter = nil
        lead.reset(); predictedWordIndex = nil
        follower.resetEvidence()
    }

    /// Supplied by the reader's display link. No timer competes with frames.
    func advanceFrame(by dt: Double) {
        guard gate.isVisible, gate.isPlaying, !gate.isHovering, !isPreparing else { return }
        let dt = min(0.1, max(0, dt))
        if gate.countdown > 0 {
            countdownRemainder -= dt
            gate.countdown = max(0, Int(ceil(countdownRemainder)))
            ignoreSpeechThrough = speech.audioSeconds
            return
        }
        advanceReading(by: dt)
    }

    /// Also used by deterministic tests; the display link supplies elapsed time.
    func advanceReading(by dt: Double) {
        guard gate.allowsAutomaticMovement, !isPreparing else { return }
        elapsed += dt
        let seconds = Int(elapsed)
        if seconds != elapsedSeconds { elapsedSeconds = seconds }
        lastRecognitionAge += dt
        if preferences.value.mode == .voice {
            voiceClock += dt
            let speaking = voiceActivity.observe(level: speech.level, at: voiceClock, dt: dt)
            if preferences.value.predictiveHighlight, !isOffScript { predictHighlight(speaking: speaking) }
            if let destination = pacedDestination(dt: dt, speaking: speaking) ?? voiceDestination {
                offset = ReadingMotion.advance(from: offset, to: destination, dt: dt,
                    reducedMotion: preferences.value.reduceMotion || systemReducesMotion())
            }
            if reachedScriptEnd, lastRecognitionAge > 1,
               voiceDestination.map({ abs($0 - offset) < 0.5 }) ?? true { pause() }
        }
        if preferences.value.mode == .automatic {
            offset = min(maximumOffset, offset + preferences.value.speed * dt)
        }
        if preferences.value.mode == .automatic, maximumOffset > 0, offset >= maximumOffset { pause() }
    }

    /// Speech-paced scrolling: the continuous offset of the estimated reading
    /// position. Frozen while off script; nil when the option is off.
    private func pacedDestination(dt: Double, speaking: Bool) -> Double? {
        guard preferences.value.speechPacedScrolling, let voiceGeometry else { return nil }
        if !isOffScript { lead.advance(by: dt, now: voiceClock, speaking: speaking) }
        guard let estimate = lead.estimate, let value = voiceGeometry(estimate) else { return nil }
        return min(maximumOffset, max(0, value))
    }

    /// Experimental: moves the highlight to the word the speaker is probably
    /// saying now, at most `predictedWordsAhead` past the recognized word.
    private func predictHighlight(speaking: Bool) {
        let tokens = follower.tokens
        let recognized = follower.nextIndex - 1
        guard activeWordRange != nil, tokens.indices.contains(recognized) else { return }
        let last = min(tokens.count - 1, recognized + Self.predictedWordsAhead)
        guard last > recognized else { return }
        lead.advanceSpoken(now: voiceClock, speaking: speaking, limit: Double(tokens[last].range.location))
        guard let spoken = lead.spoken else { return }
        // The word whose start the speaker has reached.
        var index = recognized
        while index < last, Double(tokens[index + 1].range.location) <= spoken { index += 1 }
        guard index > max(recognized, predictedWordIndex ?? recognized) else { return }
        predictedWordIndex = index
        activeWordRange = tokens[index].range
        targetCharacter = index + 1 < tokens.count ? tokens[index + 1].range.location : tokens[index].range.location
    }
}
