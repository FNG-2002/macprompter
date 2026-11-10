import Foundation
import NaturalLanguage

struct SemanticWindow: Sendable {
    let text: String
    let words: [String]
    let startIndex: Int
}

struct SemanticRecoveryRequest: Sendable {
    let revision: UInt64
    let nextIndex: Int
    let language: SpeechLanguage
    let heard: [String]
    let windows: [SemanticWindow]
    var createdUptime = ProcessInfo.processInfo.systemUptime
}

struct SemanticRecoveryEvaluation: Sendable {
    let available: Bool
    var wordIndex: Int?
    var similarity: Double = 0
    var milliseconds: Double = 0
}

protocol SemanticRecovering: Sendable {
    func available(for language: SpeechLanguage) async -> Bool
    func evaluate(_ request: SemanticRecoveryRequest) async -> SemanticRecoveryEvaluation
}

/// Immutable script metadata prepared once per script body, never per partial.
struct SemanticScriptIndex: Sendable {
    let text: String
    private let surface: [String]
    private let words: [String]
    private let boundaries: Set<Int>

    init(text: String, tokens: [ScriptToken]? = nil) {
        self.text = text
        let tokens = tokens ?? ScriptParser.words(in: text)
        let ns = text as NSString
        surface = tokens.map { ns.substring(with: $0.range) }
        words = tokens.map(\.normalized)
        var boundaries: Set<Int> = []
        if tokens.count > 1 {
            for i in 1..<tokens.count {
                let start = NSMaxRange(tokens[i - 1].range)
                let gap = ns.substring(with: NSRange(location: start, length: tokens[i].range.location - start))
                if gap.contains(where: { ".!?\n".contains($0) }) { boundaries.insert(i) }
            }
        }
        self.boundaries = boundaries
    }

    func windows(nextIndex: Int) -> [SemanticWindow] {
        guard nextIndex >= 0, nextIndex < words.count else { return [] }
        let end = min(words.count, nextIndex + 24)
        var starts = [nextIndex]
        starts += ((nextIndex + 1)..<end).filter { boundaries.contains($0) }
        starts += [nextIndex + 4, nextIndex + 8]
        var seen: Set<Int> = []
        return starts.filter { $0 < end && seen.insert($0).inserted }.prefix(4).compactMap { start in
            var stop = min(end, start + 12)
            if start + 4 < stop,
               let boundary = ((start + 4)..<stop).first(where: { boundaries.contains($0) }) { stop = boundary }
            guard stop - start >= 4 else { return nil }
            return SemanticWindow(text: surface[start..<stop].joined(separator: " "),
                words: Array(words[start..<stop]), startIndex: start)
        }
    }
}

enum SemanticCandidates {
    private static let negatives: Set<String> = ["nicht", "kein", "keine", "keinen", "keinem", "keiner", "keines", "niemals", "nie", "ohne", "not", "never", "no", "without", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "won't", "wouldn't", "can't", "cannot", "couldn't", "shouldn't"]

    /// One bounded alternative for an aside followed by a return. Keep word
    /// order/function words for the sentence model; never fish for arbitrary
    /// matching fragments or remove a negation from the discarded prefix.
    static func returnTail(heard: [String]) -> [String]? {
        guard heard.count >= 8 else { return nil }
        let cut = heard.count - 5
        guard !heard[..<cut].contains(where: { negatives.contains(ScriptParser.normalize($0)) }) else { return nil }
        let tail = Array(heard[cut...])
        guard tail.filter({ ScriptFollower.isSemanticAnchor(ScriptParser.normalize($0)) }).count >= 2 else { return nil }
        return tail
    }

    /// Convenience for tests and standalone callers. Sessions keep the index.
    static func windows(text: String, nextIndex: Int) -> [SemanticWindow] {
        SemanticScriptIndex(text: text).windows(nextIndex: nextIndex)
    }

    /// Semantics can propose a passage, but an actually spoken, distinctive
    /// word must pin the cursor. Never mark the end of a paraphrased sentence.
    static func anchor(heard: [String], window: SemanticWindow, allWindows: [SemanticWindow]) -> Int? {
        let query = heard.map(ScriptParser.normalize)
        guard query.contains(where: { negatives.contains($0) }) == window.words.contains(where: { negatives.contains($0) }) else { return nil }
        for q in query.indices.reversed().prefix(4) {
            let word = query[q]
            guard ScriptFollower.isSemanticAnchor(word) else { continue }
            let positions = window.words.indices.filter { window.words[$0] == word }
            guard positions.count == 1 else { continue }
            let distinctLocations = Set(allWindows.flatMap { candidate in
                candidate.words.indices.filter { candidate.words[$0] == word }.map { candidate.startIndex + $0 }
            })
            if distinctLocations.count == 1 { return window.startIndex + positions[0] }
        }
        return nil
    }
}

/// NLEmbedding is not thread safe. Models and all vector accesses stay inside
/// this actor. No model is shared with MainActor and no cloud fallback exists.
actor AppleSemanticRecovery: SemanticRecovering {
    private var models: [SpeechLanguage: NLEmbedding] = [:]
    private var unavailable: Set<SpeechLanguage> = []
    private var cache: [String: [Double]] = [:]
    private var cacheOrder: [String] = []

    func available(for language: SpeechLanguage) -> Bool { model(for: language) != nil }

    func evaluate(_ request: SemanticRecoveryRequest) -> SemanticRecoveryEvaluation {
        let start = ProcessInfo.processInfo.systemUptime
        guard let embedding = model(for: request.language) else { return SemanticRecoveryEvaluation(available: false) }
        var result = SemanticRecoveryEvaluation(available: true)
        // Empty speech is an explicit warm-up: cache script passages without
        // making any attempt to move the cursor.
        let queryVector = request.heard.count >= 4 ? normalized(embedding.vector(for: request.heard.joined(separator: " "))) : nil
        var scored: [Int: Double] = [:]
        for window in request.windows {
            guard !Task.isCancelled else { return result }
            let key = request.language.rawValue + "|" + window.text
            let vector: [Double]?
            if let cached = cache[key] { vector = cached }
            else {
                vector = normalized(embedding.vector(for: window.text))
                if let vector {
                    cache[key] = vector; cacheOrder.append(key)
                    if cacheOrder.count > 64 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
                }
            }
            guard let queryVector, let vector, queryVector.count == vector.count,
                  let anchor = SemanticCandidates.anchor(heard: request.heard, window: window, allWindows: request.windows),
                  anchor >= request.nextIndex, anchor < request.nextIndex + 24 else { continue }
            let similarity = zip(queryVector, vector).reduce(0) { $0 + $1.0 * $1.1 }
            scored[anchor] = max(scored[anchor] ?? -1, similarity)
        }
        // Successful full-context comparisons keep their original fast path.
        // Ambiguous full-context matches are not rescued by cherry-picking a
        // suffix. Only weak full context gets one short return attempt.
        if (scored.values.max() ?? 0) < 0.74,
           let tail = SemanticCandidates.returnTail(heard: request.heard),
           !Task.isCancelled {
            let anchored = request.windows.compactMap { window -> (SemanticWindow, Int)? in
                guard let anchor = SemanticCandidates.anchor(heard: tail, window: window, allWindows: request.windows),
                      anchor >= request.nextIndex, anchor < request.nextIndex + 24,
                      tail.suffix(2).map(ScriptParser.normalize).contains(window.words[anchor - window.startIndex]) else { return nil }
                return (window, anchor)
            }
            if !anchored.isEmpty, let shortVector = normalized(embedding.vector(for: tail.joined(separator: " "))) {
                for (window, anchor) in anchored {
                    guard let vector = cache[request.language.rawValue + "|" + window.text], vector.count == shortVector.count else { continue }
                    let similarity = zip(shortVector, vector).reduce(0) { $0 + $1.0 * $1.1 }
                    // Retain competing full-context anchors in the margin test.
                    scored[anchor] = max(scored[anchor] ?? -1, similarity)
                }
            }
        }
        let ranked = scored.sorted { $0.value > $1.value }
        result.similarity = ranked.first?.value ?? 0
        if let best = ranked.first, best.value >= 0.74,
           ranked.count == 1 || best.value - ranked[1].value >= 0.10 {
            result.wordIndex = best.key
        }
        result.milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return result
    }

    private func model(for language: SpeechLanguage) -> NLEmbedding? {
        if let model = models[language] { return model }
        guard !unavailable.contains(language) else { return nil }
        // Thresholds are measured for German and English only.
        let locale: NLLanguage? = language.code == "de" ? .german : language.code == "en" ? .english : nil
        guard let locale, let model = NLEmbedding.sentenceEmbedding(for: locale) else {
            unavailable.insert(language); return nil
        }
        models[language] = model
        return model
    }

    private func normalized(_ vector: [Double]?) -> [Double]? {
        guard let vector else { return nil }
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard length.isFinite, length > 0 else { return nil }
        return vector.map { $0 / length }
    }
}
