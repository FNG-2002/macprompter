import Foundation

struct FollowMatch {
    let wordIndices: [Int]
    let reacquired: Bool
    let confidence: Double
}

/// Online sequence alignment with a persistent local return anchor. Local
/// continuations compete with a bounded set of relocation candidates; a detour
/// never discards the anchor. Scores are evidence weights, not probabilities.
struct ScriptFollower {
    let tokens: [ScriptToken]
    private(set) var nextIndex = 0
    private(set) var isOffScript = false
    private(set) var lastMatch: FollowMatch?
    private(set) var lastInputWasRevision = false
    private(set) var lastInputWasDuplicate = false
    /// Whether the newest heard word (after spelling alignment) occurs in the script.
    private(set) var lastWordInScript = false
    private var previousWords: [String] = []
    private var precedingContext: [String] = []
    private var precedingUncommitted = 0
    private var allowedWords: [String] = []
    private var ignoredPrefix = 0
    private var acceptedThrough = 0
    private var segmentID: Double?
    private var missedWords = 0
    private var surfaceContext: [String] = []
    private var previousSurface: [String] = []
    private(set) var hasFreshEvidence = false
    private let occurrences: [String: [Int]]
    private let bridge: LexicalBridge
    private var nearMisses: [String: String?] = [:]

    init(text: String) {
        let parsed = ScriptParser.words(in: text)
        tokens = parsed
        occurrences = Dictionary(grouping: parsed.indices, by: { parsed[$0].normalized })
        bridge = LexicalBridge(tokens: parsed, text: text)
    }

    mutating func seek(character: Int) {
        nextIndex = tokens.firstIndex(where: { NSMaxRange($0.range) > character }) ?? tokens.count
        resetEvidence()
    }

    mutating func resetEvidence() {
        previousWords = []; precedingContext = []; precedingUncommitted = 0; allowedWords = []
        ignoredPrefix = 0; acceptedThrough = 0; segmentID = nil; missedWords = 0; isOffScript = false; lastMatch = nil
        surfaceContext = []; previousSurface = []; hasFreshEvidence = false
        lastInputWasDuplicate = false; nearMisses = [:]
    }

    mutating func consume(_ text: String, segment: Double, accepting: Bool) -> Int? {
        lastMatch = nil
        hasFreshEvidence = false
        lastInputWasRevision = false
        let newSegment = segmentID != segment
        if newSegment { nearMisses = [:] }
        let spoken = bridge.spoken(text) as NSString
        let heard = bridge.map(ScriptParser.words(in: spoken as String).map {
            LexicalBridge.Word(normalized: $0.normalized, surface: spoken.substring(with: $0.range))
        })
        var words = heard.map(\.normalized)
        // Inflection or a single misheard letter only near the expected
        // position, never while off script and never for distant jumps.
        if !isOffScript {
            for i in words.indices where !bridge.vocabulary.contains(words[i]) {
                if let near = nearMiss(words[i]) { words[i] = near }
            }
        }
        // Punctuation/case-only updates describe the same word evidence. A
        // different audio segment is new speech even when its words repeat.
        lastInputWasDuplicate = !newSegment && words == previousWords
        if newSegment {
            surfaceContext = Array((surfaceContext + previousSurface.dropFirst(ignoredPrefix)).suffix(11))
            precedingUncommitted = min(11, precedingUncommitted + max(0, previousWords.count - max(acceptedThrough, ignoredPrefix)))
            precedingContext = Array((precedingContext + allowedWords).suffix(11))
            previousWords = []; ignoredPrefix = 0; acceptedThrough = 0; segmentID = segment
        }
        let common = zip(previousWords, words).prefix(while: { $0 == $1 }).count
        let revision = !newSegment && common < previousWords.count
        lastInputWasRevision = revision
        previousWords = words
        previousSurface = heard.map(\.surface)
        guard accepting else {
            ignoredPrefix = words.count; precedingContext = []; precedingUncommitted = 0; allowedWords = []
            missedWords = 0
            surfaceContext = []
            return nil
        }
        // A volatile revision of already consumed audio is not new speech.
        // Without this frontier, correcting "panel" back to "panels" can jump
        // over the next identical sentence in a repetitive script.
        if revision && words.count <= acceptedThrough { return nil }
        allowedWords = Array(words.dropFirst(ignoredPrefix))
        guard common < words.count, !tokens.isEmpty, !allowedWords.isEmpty else { return nil }
        var full = precedingContext + allowedWords
        // Only non-lexical hesitation sounds may trail a confirmed batch.
        // Never drop "also", "actually", etc., or an expected script token.
        var trailingHesitations = 0
        while let last = full.last, Self.hesitations.contains(last),
              !(nextIndex..<min(tokens.count, nextIndex + 6)).contains(where: { tokens[$0].normalized == last }) {
            full.removeLast(); trailingHesitations += 1
        }
        // Fast results often end in a partial word ("Spei" for "Speicher").
        // It must neither block the complete words before it nor count as
        // consumed, so the next result can still match the finished word.
        var fragment = 0
        if let last = full.last, isFragment(last),
           words.count - max(common, ignoredPrefix, revision ? acceptedThrough : 0) - trailingHesitations > 1 {
            full.removeLast(); fragment = 1
        }
        let pending = trailingHesitations + fragment
        let consumed = words.count - fragment
        let query = Array(full.suffix(12))
        let freshCount = min(words.count - max(common, ignoredPrefix, revision ? acceptedThrough : 0) - pending, query.count)
        guard freshCount > 0, let last = query.last else { return nil }
        lastWordInScript = occurrences[last] != nil
        hasFreshEvidence = true
        let freshStart = query.count - freshCount
        let uncommittedStart = max(0, query.count - precedingUncommitted - (words.count - max(acceptedThrough, ignoredPrefix) - pending))
        // The small local window is evaluated first. A distinctive expected
        // word, or a coherent two-word return, need not wait for a global scan.
        let localCandidates = (nextIndex..<min(tokens.count, nextIndex + 6)).filter { tokens[$0].normalized == last }
            .compactMap { align(query, endingAt: $0, freshStart: freshStart, uncommittedStart: uncommittedStart) }
        let local = localCandidates.filter({ acceptsLocal($0, query: query, freshStart: freshStart, uncommittedStart: uncommittedStart) })
            .max(by: { rank($0) < rank($1) })
        let freshContentCount = query[freshStart...].filter { !Self.fillers.contains($0) }.count
        if let local, freshContentCount <= 2 || local.newMatches >= freshContentCount - 1 {
            return commit(local, wordsCount: consumed, freshStart: freshStart)
        }
        let endpoints = occurrences[last] ?? []
        // An inverted word index makes even a distant re-entry cheap. Common
        // words get at most 240 candidate positions, nearest first.
        let candidates = nearestEndpoints(endpoints, limit: 240)
            .compactMap { align(query, endingAt: $0, freshStart: freshStart, uncommittedStart: uncommittedStart) }
        let eligible = candidates.filter { candidate in
            let distance = candidate.end + 1 - nextIndex
            let backward = distance <= 0
            let far = abs(distance) > 24
            guard candidate.newMatches > 0, !candidate.pairs.isEmpty else { return false }
            // Corrected volatile text may improve alignment, but must not rewind.
            if backward && revision { return false }
            if isOffScript && !backward && !far && tokens.count - nextIndex <= 3 {
                let remaining = tokens.count - nextIndex
                return candidate.end == tokens.count - 1 && candidate.uncommittedMatches >= remaining
                    && candidate.tailMatches >= remaining && candidate.informative >= 1
            }
            if backward || far || isOffScript {
                return candidate.uncommittedMatches >= 4 && candidate.informative >= 2
                    && candidate.coverage >= 0.78 && candidate.tailMatches >= 2
            }
            return candidate.uncommittedMatches >= 2 && candidate.coverage >= 0.7 && candidate.tailMatches >= 2
        }.sorted { rank($0) > rank($1) }

        // A full return phrase may end on the next local word by coincidence.
        // Let a substantially stronger global phrase compete in that case;
        // a single local anchor must not swallow explicit backward re-entry.
        if let local, eligible.first.map({ $0.uncommittedMatches < 4 || $0.score <= local.score + 3 }) ?? true {
            return commit(local, wordsCount: consumed, freshStart: freshStart)
        }
        guard let best = eligible.first else {
            if let nearby = flexibleReturn(query, freshStart: freshStart, uncommittedStart: uncommittedStart) {
                return commit(nearby, wordsCount: consumed, freshStart: freshStart)
            }
            missedWords += freshCount
            if missedWords >= 4 { isOffScript = true }
            return nil
        }
        let distance = best.end + 1 - nextIndex
        let recovering = isOffScript || distance <= 0 || distance > 24
        if recovering {
            // Identical phrases in several places are not enough to relocate.
            // Wait for the next distinguishing words instead of guessing.
            let ambiguous = candidates.contains {
                abs($0.end - best.end) > 3 && $0.matches >= best.matches
                    && $0.coverage >= best.coverage - 0.05 && abs($0.score - best.score) < 2
            }
            if ambiguous { isOffScript = true; return nil }
        }
        return commit(best, wordsCount: consumed, freshStart: freshStart)
    }

    /// A trailing word that is not in the script, or only the beginning of
    /// one of the next script words, is still being spoken.
    private func isFragment(_ word: String) -> Bool {
        guard !Self.hesitations.contains(word) else { return false }
        guard bridge.vocabulary.contains(word) else { return true }
        let upcoming = (nextIndex..<min(tokens.count, nextIndex + 6)).map { tokens[$0].normalized }
        return !upcoming.contains(word) && upcoming.contains { $0.count > word.count && $0.hasPrefix(word) }
    }

    /// Only unconsumed speech may support the experimental model. Preserve
    /// accents/case for Apple's language model; lexical checks normalize later.
    func semanticEvidence() -> [String] {
        guard hasFreshEvidence, lastMatch == nil else { return [] }
        let count = precedingUncommitted + max(0, previousWords.count - max(acceptedThrough, ignoredPrefix))
        return Array((surfaceContext + previousSurface.dropFirst(ignoredPrefix)).suffix(min(12, count))).filter { !$0.isEmpty }
    }

    /// Cached per audio segment, so later volatile updates of the same words
    /// keep their mapping after the position advanced.
    private mutating func nearMiss(_ word: String) -> String? {
        if let cached = nearMisses[word] { return cached }
        guard !Self.fillers.contains(word) else { return nil }
        let forms = Set((nextIndex..<min(tokens.count, nextIndex + 8)).map { tokens[$0].normalized }
            .filter { Self.isInformative($0) && !Self.fillers.contains($0) && LexicalBridge.isNearMiss(word, of: $0) })
        let near = forms.count == 1 ? forms.first : nil
        nearMisses[word] = near
        return near
    }

    mutating func acceptSemanticAnchor(_ index: Int, expectedNextIndex: Int) -> Bool {
        guard nextIndex == expectedNextIndex, index >= nextIndex, index < min(tokens.count, nextIndex + 24) else { return false }
        nextIndex = index + 1
        acceptedThrough = previousWords.count; precedingUncommitted = 0
        isOffScript = false; missedWords = 0; hasFreshEvidence = false
        lastMatch = FollowMatch(wordIndices: [index], reacquired: true, confidence: 0)
        return true
    }

    static func isSemanticAnchor(_ word: String) -> Bool {
        isInformative(word) && !fillers.contains(word) && !weakReturnWords.contains(word)
    }

    /// Last-resort local recovery, not semantic matching: exact distinctive
    /// anchors may bridge a few changed words in the next 16 script tokens.
    /// Neither already consumed evidence nor trailing asides can drive it.
    private func flexibleReturn(_ query: [String], freshStart: Int, uncommittedStart: Int) -> Candidate? {
        let window = nextIndex..<min(tokens.count, nextIndex + 16)
        guard window.count >= 2, uncommittedStart < query.count else { return nil }
        let locations = Dictionary(grouping: window, by: { tokens[$0].normalized })
        var paths: [[Pair]] = []
        for q in uncommittedStart..<query.count {
            let word = query[q]
            guard Self.isInformative(word), !Self.fillers.contains(word), !Self.weakReturnWords.contains(word),
                  let positions = locations[word], positions.count == 1 else { continue }
            let pair = Pair(query: q, script: positions[0])
            var extensions = [[pair]]
            for path in paths {
                guard let previous = path.last, path.count < 4,
                      pair.query > previous.query, pair.script > previous.script,
                      pair.query - previous.query <= 4, pair.script - previous.script <= 4 else { continue }
                extensions.append(path + [pair])
            }
            // At most four alternatives per endpoint, at most twelve heard
            // tokens: keep CPU and storage bounded even with repeated speech.
            paths += extensions.sorted { returnScore($0) > returnScore($1) }.prefix(4)
        }
        let eligible = paths.filter { path in
            guard let first = path.first, let last = path.last, path.count >= 2,
                  last.query >= freshStart, query.count - last.query - 1 <= 3 else { return false }
            let advance = last.script + 1 - nextIndex
            let lead = first.script - nextIndex
            let required = advance > 10 || lead > 6 ? 3 : 2
            let gap = max(last.query - first.query, last.script - first.script) + 1 - path.count
            return path.count >= required && lead <= 10 && gap <= (path.count == 2 ? 3 : 5)
        }.sorted { returnScore($0) > returnScore($1) }
        guard let best = eligible.first, let first = best.first, let last = best.last else { return nil }
        // Two unrelated, equally strong local phrases must not make the
        // decision arbitrary. Shared anchors describe the same continuation.
        if eligible.dropFirst().contains(where: { other in
            abs(other.last!.script - last.script) > 3
                && abs(returnScore(other) - returnScore(best)) < 1.5
                && !other.contains(where: { p in best.contains(where: { $0.script == p.script }) })
        }) { return nil }
        let span = max(last.query - first.query, last.script - first.script) + 1
        return Candidate(end: last.script, score: returnScore(best), pairs: best,
            coverage: Double(best.count) / Double(span), tailMatches: 0, informative: best.count,
            newMatches: best.filter { $0.query >= freshStart }.count, uncommittedMatches: best.count)
    }

    private func returnScore(_ path: [Pair]) -> Double {
        guard let first = path.first, let last = path.last else { return 0 }
        let gaps = max(last.query - first.query, last.script - first.script) + 1 - path.count
        return Double(path.count) * 4 - Double(gaps) * 0.7 - Double(first.script - nextIndex) * 0.1
    }

    private mutating func commit(_ best: Candidate, wordsCount: Int, freshStart: Int) -> Int? {
        let distance = best.end + 1 - nextIndex
        let recovering = isOffScript || distance <= 0 || distance > 24
        let oldIndex = nextIndex
        nextIndex = best.end + 1
        acceptedThrough = wordsCount
        precedingUncommitted = 0
        isOffScript = false; missedWords = 0
        let indices = best.pairs.filter { $0.query >= freshStart && (recovering || $0.script >= oldIndex) }.map(\.script)
        lastMatch = FollowMatch(wordIndices: indices.isEmpty ? [best.end] : indices,
                                reacquired: recovering, confidence: best.coverage)
        return nextIndex < tokens.count ? tokens[nextIndex].range.location : NSMaxRange(tokens.last!.range)
    }

    private func acceptsLocal(_ candidate: Candidate, query: [String], freshStart: Int, uncommittedStart: Int) -> Bool {
        guard candidate.newMatches > 0 else { return false }
        let distance = candidate.end + 1 - nextIndex
        if distance == 1 {
            let firstFresh = candidate.pairs.first(where: { $0.query >= freshStart })?.query ?? query.count
            let precedingUnknown = query[freshStart..<firstFresh].filter { !Self.fillers.contains($0) }.count
            // A whole aside may arrive in one batch ending with "the".
            // Such a word is not evidence of uninterrupted reading.
            if !isOffScript && precedingUnknown < 3 { return true }
            let word = tokens[nextIndex].normalized
            let neighborhood = max(0, nextIndex - 12)..<min(tokens.count, nextIndex + 13)
            return Self.isInformative(word) && !Self.fillers.contains(word)
                && (occurrences[word] ?? []).filter({ neighborhood.contains($0) }).count == 1
        }
        // A small set of local hypotheses is represented by alignment paths.
        // Only the trailing coherent run counts as new return evidence: old
        // matches, or coincidental words scattered through an anecdote, cannot.
        let pairs = candidate.pairs.filter { $0.query >= uncommittedStart && $0.script >= nextIndex }
        guard let last = pairs.last else { return false }
        var run = [last]
        for pair in pairs.dropLast().reversed() {
            let next = run.last!
            guard next.script == pair.script + 1, next.query - pair.query <= 4,
                  query[(pair.query + 1)..<next.query].allSatisfy({ Self.fillers.contains($0) }) else { break }
            run.append(pair)
        }
        guard run.count >= 2, let first = run.last else { return false }
        let informative = run.filter { Self.isInformative(query[$0.query]) && !Self.fillers.contains(query[$0.query]) }.count
        if first.script == nextIndex { return !isOffScript || informative >= 1 }
        // One missing/misrecognized script word is tolerable with two strong
        // neighbors. Larger omissions keep the conservative relocation rules.
        return first.script == nextIndex + 1 && informative >= 2
    }

    /// Occurrences are already in script order. Binary search + a two-sided
    /// walk avoids sorting an entire repetitive script for every common word.
    private func nearestEndpoints(_ endpoints: [Int], limit: Int) -> [Int] {
        var lower = 0, upper = endpoints.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if endpoints[middle] < nextIndex { lower = middle + 1 } else { upper = middle }
        }
        var left = lower - 1, right = lower, result: [Int] = []
        while result.count < limit && (left >= 0 || right < endpoints.count) {
            if right < endpoints.count && (left < 0 || abs(endpoints[right] + 1 - nextIndex) <= abs(endpoints[left] + 1 - nextIndex)) {
                result.append(endpoints[right]); right += 1
            } else { result.append(endpoints[left]); left -= 1 }
        }
        return result
    }

    private struct Pair { let query: Int; let script: Int }
    private struct Candidate {
        let end: Int
        let score: Double
        let pairs: [Pair]
        let coverage: Double
        let tailMatches: Int
        let informative: Int
        let newMatches: Int
        let uncommittedMatches: Int
        var matches: Int { pairs.count }
    }

    private func rank(_ c: Candidate) -> Double {
        // Strong language evidence outweighs proximity; equally good local
        // phrases choose the next occurrence, rather than an earlier repetition.
        let distance = c.end + 1 - nextIndex
        return Double(c.score) - min(4, Double(abs(distance)) * 0.035) - (distance <= 0 ? 2 : 0)
    }

    private func align(_ query: [String], endingAt end: Int, freshStart: Int, uncommittedStart: Int) -> Candidate? {
        let start = max(0, end - query.count - 2)
        let script = Array(tokens[start...end])
        let rows = query.count + 1, cols = script.count + 1
        var scores = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        var insertions = scores
        var extendingInsertion = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var directions = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        for q in 1..<rows {
            for s in 1..<cols {
                let equal = query[q - 1] == script[s - 1].normalized
                let diagonal = scores[q - 1][s - 1] + (equal ? 3 : -3)
                let filler = Self.fillers.contains(query[q - 1])
                let opened = scores[q - 1][s] - (filler ? 0.4 : 3)
                let extended = insertions[q - 1][s] - (filler ? 0.2 : 0.6)
                let inserted = max(opened, extended)
                insertions[q][s] = inserted
                extendingInsertion[q][s] = extended > opened
                let omitted = scores[q][s - 1] - 3
                let best = max(0, diagonal, inserted, omitted)
                scores[q][s] = best
                directions[q][s] = best == 0 ? 0 : (best == diagonal ? 1 : (best == inserted ? 2 : 3))
            }
        }
        var q = query.count, s = script.count
        var pairs: [Pair] = []
        let score = scores[q][s]
        var tailMatches = 0, inTail = true
        while q > 0, s > 0, scores[q][s] > 0 {
            switch directions[q][s] {
            case 1:
                if query[q - 1] == script[s - 1].normalized {
                    pairs.append(Pair(query: q - 1, script: start + s - 1))
                    if inTail { tailMatches += 1 }
                } else { inTail = false }
                q -= 1; s -= 1
            case 2:
                // Trace the affine insertion state, not a different best path
                // that happens to occupy the preceding cell.
                var more = true
                while q > 0 && more {
                    more = extendingInsertion[q][s]
                    q -= 1
                }
                inTail = false
            case 3: s -= 1; inTail = false
            default: return nil
            }
        }
        guard !pairs.isEmpty else { return nil }
        pairs.reverse()
        let coverage = Double(pairs.count) / Double(max(query.count - q, script.count - s))
        let informative = pairs.filter { $0.query >= uncommittedStart && Self.isInformative(query[$0.query]) }.count
        return Candidate(end: end, score: score, pairs: pairs, coverage: coverage, tailMatches: tailMatches,
                         informative: informative, newMatches: pairs.filter { $0.query >= freshStart }.count, uncommittedMatches: pairs.filter { $0.query >= uncommittedStart }.count)
    }

    private static func isInformative(_ word: String) -> Bool {
        word.count >= 4 && !stopWords.contains(word)
    }
    private static let hesitations: Set<String> = ["ah", "ahm", "eh", "ehm", "uh", "uhm", "um", "erm"]
    private static let fillers: Set<String> = hesitations.union([
        "also", "eigentlich", "genau", "naja", "halt", "eben", "sozusagen", "quasi",
        "actually", "well", "basically", "like"
    ])
    private static let weakReturnWords: Set<String> = [
        "heute", "morgen", "jetzt", "danach", "anschliessend", "nachsten", "diesem", "dieses", "diesen",
        "unsere", "unserer", "unserem", "next", "after", "before", "later", "today", "tomorrow"
    ]
    private static let stopWords: Set<String> = [
        "aber", "also", "auch", "dann", "dass", "dies", "diese", "dieser", "eine", "einen", "einem", "einer",
        "habe", "haben", "hier", "ihnen", "kann", "mein", "meine", "nicht", "noch", "oder", "sich", "sind", "uber", "wird", "werden",
        "about", "also", "been", "from", "have", "just", "more", "some", "that", "their", "them", "then", "there", "these", "they", "this", "very", "were", "what", "when", "which", "will", "with", "would", "your"
    ]
}

/// Frame-rate independent, monotonic settling. A known destination continues
/// settling during speech silence, but never extrapolates beyond that line.
enum ReadingMotion {
    static func advance(from current: Double, to target: Double, dt: Double, reducedMotion: Bool) -> Double {
        guard dt > 0 else { return current }
        if reducedMotion || abs(target - current) < 0.25 { return target }
        // Gentle near the reading line, quicker when several lines behind.
        let catchUp = min(1, max(0, (abs(target - current) - 40) / 240))
        let response = 0.16 - 0.08 * catchUp
        let step = (target - current) * (1 - exp(-min(dt, 0.1) / response))
        let limit = 2200 * min(dt, 0.1)
        return current + min(limit, max(-limit, step))
    }
}
