import Foundation

/// No audio or transcript is retained. Audio-to-wall-clock mapping is an
/// estimate from tap delivery, not a measurement of physical microphone delay.
struct SpeechAudioClock {
    private var originUptime: Double?

    mutating func observe(audioEnd: Double, deliveredAt uptime: Double) {
        guard audioEnd.isFinite, uptime.isFinite else { return }
        let origin = uptime - audioEnd
        originUptime = min(originUptime ?? origin, origin)
    }

    func uptime(for audioTime: Double) -> Double? {
        guard audioTime.isFinite else { return nil }
        return originUptime.map { $0 + audioTime }
    }
}

struct SpeechResultTiming {
    let receivedUptime: Double
    var estimatedAudioEndUptime: Double?
    /// Final results: for each timed word, first appearance minus its end (ms).
    var wordLatencies: [Double] = []
    /// Final results: timed words that never appeared in a volatile result.
    var wordsOnlyInFinal = 0
    /// Volatile results that brought new words: time since the previous such result (ms).
    var newWordGap: Double?
}

/// Volatile results carry one time range for their whole text; only final
/// results time each word. So a word's latency is measured afterwards: its
/// first appearance in a volatile result against its own end in the final.
/// Segment starts move as parts finalize, so appearances are matched by word
/// and time, not by segment. Words stay in memory for at most 30 s.
struct WordAppearanceTracker {
    private var appearances: [String: [Double]] = [:]
    private var previousCounts: [String: Int] = [:]
    private var previousSegment: Double?
    private var lastUpdate: Double?

    /// Returns the gap to the previous burst of results (the recognizer's
    /// update rhythm); results within 50 ms belong to the same burst.
    mutating func volatile(_ words: [String], segment: Double, at uptime: Double) -> Double? {
        let counts = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        let before = segment == previousSegment ? previousCounts : [:]
        for (word, count) in counts where count > before[word, default: 0] {
            appearances[word, default: []] += Array(repeating: uptime, count: count - before[word, default: 0])
        }
        previousCounts = counts; previousSegment = segment
        appearances = appearances.compactMapValues { times in
            let recent = times.filter { uptime - $0 < 30 }
            return recent.isEmpty ? nil : recent
        }
        defer { lastUpdate = uptime }
        guard let last = lastUpdate, uptime - last > 0.05, uptime - last <= 2 else { return nil }
        return (uptime - last) * 1000
    }

    /// A complete word cannot appear long before it ends; an earlier
    /// appearance belongs to an earlier occurrence of the same word.
    /// Words that only the final result shows (written differently while
    /// volatile, or added on finalization) are counted, not timed: their
    /// finalization can come seconds later and says nothing about following.
    mutating func final(_ words: [(word: String, endUptime: Double?)], at uptime: Double) -> (latencies: [Double], unseen: Int) {
        var unseen = 0
        let latencies = words.compactMap { word, end -> Double? in
            guard let end else { return nil }
            var times = appearances[word] ?? []
            guard let index = times.indices.filter({ times[$0] >= end - 0.25 }).min(by: { times[$0] < times[$1] }) else {
                unseen += 1; return nil
            }
            let seen = times.remove(at: index); appearances[word] = times
            return max(0, (seen - end) * 1000)
        }
        return (latencies, unseen)
    }
}

/// Why a speech event did or did not move the position; counts only.
enum SpeechEventOutcome: CaseIterable {
    case advanced, duplicate, revision, nothingNew, paused
    /// Fresh words without progress: the newest word is not in the script,
    /// it is but the position is not yet unambiguous, or during an aside.
    case unknownWord, ambiguous, offScript
}

/// Bounded, in-memory diagnostics, inspectable in tests/the debugger. The view
/// records when it applies highlight attributes; that is not display scanout.
struct SpeechLatencyMetrics {
    struct Sample {
        let id: UInt64
        let receivedUptime: Double
        let recognitionMilliseconds: Double?
        let trackerMilliseconds: Double
        let revised: Bool
        let outcome: SpeechEventOutcome
        var matched: Bool { outcome == .advanced }
        var highlightMilliseconds: Double?
    }

    private(set) var samples: [Sample] = []
    private(set) var wordMilliseconds: [Double] = []
    private(set) var newWordGaps: [Double] = []
    private(set) var wordsOnlyInFinal = 0
    /// Re-entries found by the sentence model after the word tracker failed.
    private(set) var semanticReturns = 0
    private var sequence: UInt64 = 0

    mutating func record(timing: SpeechResultTiming, trackerSeconds: Double, revised: Bool, matched: Bool, outcome: SpeechEventOutcome? = nil) -> UInt64 {
        sequence &+= 1
        func delay(_ end: Double?) -> Double? {
            end.flatMap { end in
                let delay = timing.receivedUptime - end
                return delay >= 0 && delay.isFinite ? delay * 1000 : nil
            }
        }
        samples.append(Sample(id: sequence, receivedUptime: timing.receivedUptime,
            recognitionMilliseconds: delay(timing.estimatedAudioEndUptime),
            trackerMilliseconds: max(0, trackerSeconds * 1000),
            revised: revised, outcome: outcome ?? (matched ? .advanced : .ambiguous)))
        if samples.count > 256 { samples.removeFirst(samples.count - 256) }
        wordMilliseconds = Array((wordMilliseconds + timing.wordLatencies).suffix(512))
        if let gap = timing.newWordGap { newWordGaps = Array((newWordGaps + [gap]).suffix(256)) }
        wordsOnlyInFinal += timing.wordsOnlyInFinal
        return sequence
    }

    mutating func recordSemanticReturn() { semanticReturns += 1 }

    mutating func appliedHighlight(sampleID: UInt64, at uptime: Double) {
        guard let index = samples.lastIndex(where: { $0.id == sampleID }),
              samples[index].highlightMilliseconds == nil else { return }
        samples[index].highlightMilliseconds = max(0, (uptime - samples[index].receivedUptime) * 1000)
    }
}

/// What the settings show for the last take: timings and counts only, never
/// words. Percentiles use the nearest rank of the bounded sample window.
struct SpeechLatencySummary: Equatable {
    struct Spread: Equatable {
        let median: Double
        let p95: Double
    }

    let events: Int
    let advanced: Int
    let revised: Int
    let recognition: Spread?
    let word: Spread?
    /// How often volatile results bring new words (the recognizer's rhythm).
    let newWords: Spread?
    let wordsOnlyInFinal: Int
    let tracker: Spread?
    let highlight: Spread?
    /// Results that arrived at least one second after their audio ended.
    let slowRecognitions: Int
    let outcomes: [SpeechEventOutcome: Int]

    init(_ samples: [SpeechLatencyMetrics.Sample], words: [Double] = [], newWordGaps: [Double] = [], wordsOnlyInFinal: Int = 0) {
        events = samples.count
        advanced = samples.filter(\.matched).count
        revised = samples.filter(\.revised).count
        let recognitions = samples.compactMap(\.recognitionMilliseconds)
        recognition = Self.spread(recognitions)
        word = Self.spread(words)
        newWords = Self.spread(newWordGaps)
        self.wordsOnlyInFinal = wordsOnlyInFinal
        outcomes = Dictionary(grouping: samples, by: \.outcome).mapValues(\.count)
        tracker = Self.spread(samples.map(\.trackerMilliseconds))
        highlight = Self.spread(samples.compactMap(\.highlightMilliseconds))
        slowRecognitions = recognitions.filter { $0 >= 1000 }.count
    }

    static func spread(_ values: [Double]) -> Spread? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func rank(_ quantile: Double) -> Double { sorted[max(0, Int((Double(sorted.count) * quantile).rounded(.up)) - 1)] }
        return Spread(median: rank(0.5), p95: rank(0.95))
    }
}

extension SpeechLatencyMetrics {
    var summary: SpeechLatencySummary { SpeechLatencySummary(samples, words: wordMilliseconds, newWordGaps: newWordGaps, wordsOnlyInFinal: wordsOnlyInFinal) }
}
