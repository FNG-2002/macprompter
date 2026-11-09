import Foundation

/// Maps heard words onto the script's own spelling before alignment. Apple's
/// recognizer writes "25" for "fünfundzwanzig", "drei" for "3", "Dr." for
/// "Doktor" or "email" for "E-Mail"; formatting must not count as a different
/// word. Only fixed equivalences that occur in this script are used, and a
/// heard sequence that exists verbatim in the script is never rewritten. The
/// alignment rules and thresholds stay untouched.
struct LexicalBridge {
    struct Word: Equatable {
        let normalized: String
        let surface: String
    }

    let vocabulary: Set<String>
    private let phrases: Set<String>
    private let equivalents: [String: [String]]
    private let percentWord: String?
    private static let maxLength = 4

    init(tokens: [ScriptToken], text: String) {
        let words = tokens.map(\.normalized)
        let vocabulary = Set(words)
        self.vocabulary = vocabulary
        let ns = text as NSString
        // Hyphenated or slashed parts ("E-Mail", "Ende-zu-Ende") may be heard
        // as one word; whitespace-separated script words may not be merged.
        let joinedToNext = tokens.indices.map { i -> Bool in
            guard i + 1 < tokens.count else { return false }
            let gap = NSRange(location: NSMaxRange(tokens[i].range), length: tokens[i + 1].range.location - NSMaxRange(tokens[i].range))
            return gap.length <= 2 && ns.substring(with: gap).rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }
        var phrases = Set<String>(), equivalents: [String: [String]] = [:]
        for start in words.indices {
            for length in 1...min(Self.maxLength, words.count - start) {
                let gram = Array(words[start..<(start + length)])
                if length > 1 { phrases.insert(gram.joined(separator: " ")) }
                let joined = (start..<(start + length - 1)).allSatisfy { joinedToNext[$0] }
                for key in Self.keys(gram, concatenate: joined) where equivalents[key] == nil {
                    equivalents[key] = gram
                }
            }
        }
        // "25 %" is one word in the script, "25 Prozent" two when heard.
        if text.contains("%") {
            for word in ["prozent", "percent"] where !vocabulary.contains(word) { equivalents["c" + word] = [] }
        }
        percentWord = ["prozent", "percent"].first { vocabulary.contains($0) }
        self.phrases = phrases
        self.equivalents = equivalents
    }

    /// The recognizer formats "25 Prozent" as "25%" in English; "%" is not a word token.
    func spoken(_ text: String) -> String {
        guard let percentWord, text.contains("%") else { return text }
        return text.replacingOccurrences(of: "%", with: " \(percentWord) ")
    }

    func map(_ heard: [Word]) -> [Word] {
        var result: [Word] = []
        var start = 0
        while start < heard.count {
            guard let (sequence, length) = equivalent(at: start, in: heard) else {
                result.append(heard[start]); start += 1; continue
            }
            let surface = heard[start..<(start + length)].map(\.surface).joined(separator: " ")
            result += sequence.enumerated().map { Word(normalized: $1, surface: $0 == 0 ? surface : "") }
            start += length
        }
        return result
    }

    private func equivalent(at start: Int, in heard: [Word]) -> ([String], Int)? {
        for length in stride(from: min(Self.maxLength, heard.count - start), through: 1, by: -1) {
            let gram = heard[start..<(start + length)].map(\.normalized)
            if length == 1 ? vocabulary.contains(gram[0]) : phrases.contains(gram.joined(separator: " ")) { return nil }
            for key in Self.keys(gram, concatenate: true) {
                if let sequence = equivalents[key], sequence != gram { return (sequence, length) }
            }
        }
        return nil
    }

    private static func keys(_ gram: [String], concatenate: Bool) -> [String] {
        var keys: [String] = []
        if concatenate && gram.count <= 3 { keys.append("c" + gram.joined()) }
        if let value = number(gram) { keys.append("n\(value)") }
        for group in aliasLookup[gram.joined(separator: " ")] ?? [] { keys.append("a\(group)") }
        return keys
    }

    // MARK: Numbers

    static func number(_ gram: [String]) -> Int? {
        if gram.count == 1 {
            let word = gram[0]
            if word.count <= 9, !word.isEmpty, word.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) { return Int(word) }
            if let value = german(word) { return value }
        }
        return english(gram)
    }

    private static let germanUnits = [
        "eins": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4, "funf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
        "zehn": 10, "elf": 11, "zwolf": 12, "dreizehn": 13, "vierzehn": 14, "funfzehn": 15, "sechzehn": 16,
        "siebzehn": 17, "achtzehn": 18, "neunzehn": 19, "zwanzig": 20, "dreissig": 30, "vierzig": 40,
        "funfzig": 50, "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90
    ]
    private static let germanPrefixes = ["ein": 1, "zwei": 2, "drei": 3, "vier": 4, "funf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9]

    /// German cardinals are single words: "zweitausendsechsundzwanzig".
    private static func german(_ word: String) -> Int? {
        guard let split = word.range(of: "tausend") else { return germanBelowThousand(word) }
        let head = String(word[..<split.lowerBound]), tail = String(word[split.upperBound...])
        guard let thousands = head.isEmpty || head == "ein" ? 1 : germanBelowThousand(head),
              let rest = tail.isEmpty ? 0 : germanBelowThousand(tail) else { return nil }
        return thousands * 1000 + rest
    }

    private static func germanBelowThousand(_ word: String) -> Int? {
        guard let split = word.range(of: "hundert") else { return germanBelowHundred(word) }
        let head = String(word[..<split.lowerBound]), tail = String(word[split.upperBound...])
        guard let hundreds = head.isEmpty ? 1 : germanPrefixes[head],
              let rest = tail.isEmpty ? 0 : germanBelowHundred(tail) else { return nil }
        return hundreds * 100 + rest
    }

    private static func germanBelowHundred(_ word: String) -> Int? {
        if let value = germanUnits[word] { return value }
        guard let split = word.range(of: "und"), let unit = germanPrefixes[String(word[..<split.lowerBound])],
              let tens = germanUnits[String(word[split.upperBound...])], tens >= 20, tens % 10 == 0 else { return nil }
        return unit + tens
    }

    private static let englishUnits = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let englishTens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]

    /// English cardinals span words ("twenty five", "one hundred and twelve");
    /// malformed orders such as "five twenty" are not a number.
    private static func english(_ gram: [String]) -> Int? {
        enum Part { case none, unit, ten, hundred, thousand, and }
        var total = 0, current = 0, last = Part.none
        for word in gram {
            if let value = englishUnits[word] {
                guard last != .unit, !(last == .ten && value >= 10) else { return nil }
                current += value; last = .unit
            } else if let value = englishTens[word] {
                guard last != .unit, last != .ten else { return nil }
                current += value; last = .ten
            } else if word == "hundred" {
                guard last == .unit || last == .ten else { return nil }
                current *= 100; last = .hundred
            } else if word == "thousand" {
                guard last != .none, last != .and, last != .thousand, current > 0 else { return nil }
                total += current * 1000; current = 0; last = .thousand
            } else if word == "and" {
                guard last == .hundred || last == .thousand else { return nil }
                last = .and
            } else { return nil }
        }
        return last == .none || last == .and ? nil : total + current
    }

    // MARK: Abbreviations and contractions

    /// Normalized variants, separated by "|". German dictation spells out
    /// "zum Beispiel", English writes "Dr." and "etc." (measured with
    /// SpeechTranscriber on 27 October 2026).
    private static let aliasGroups = [
        "z b|zum beispiel", "d h|das heisst", "u a|unter anderem", "usw|und so weiter", "bzw|beziehungsweise",
        "z t|zum teil", "ca|circa|zirka", "evtl|eventuell", "ggf|gegebenenfalls", "inkl|inklusive", "nr|nummer",
        "mio|million|millionen", "mrd|milliarde|milliarden", "dr|doktor|doctor", "prof|professor",
        "e g|for example", "i e|that is", "etc|et cetera", "vs|versus", "mr|mister",
        "don't|do not", "doesn't|does not", "didn't|did not", "isn't|is not", "aren't|are not", "wasn't|was not",
        "weren't|were not", "can't|cannot|can not", "won't|will not", "wouldn't|would not", "couldn't|could not",
        "shouldn't|should not", "haven't|have not", "hasn't|has not", "it's|it is", "that's|that is",
        "there's|there is", "what's|what is", "let's|let us", "i'm|i am", "you're|you are", "we're|we are",
        "they're|they are", "i've|i have", "we've|we have", "you've|you have", "they've|they have",
        "i'll|i will", "we'll|we will", "you'll|you will", "it'll|it will", "i'd|i would", "we'd|we would",
        "gibt's|gibt es", "geht's|geht es"
    ]
    private static let aliasLookup: [String: [Int]] = {
        var lookup: [String: [Int]] = [:]
        for (group, variants) in aliasGroups.enumerated() {
            for variant in variants.split(separator: "|") { lookup[String(variant), default: []].append(group) }
        }
        return lookup
    }()

    // MARK: Near misses

    /// Bounded Levenshtein distance; nil once the limit is exceeded.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int? {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        guard abs(a.count - b.count) <= limit else { return nil }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            guard current.min()! <= limit else { return nil }
            previous = current
        }
        return previous[b.count] <= limit ? previous[b.count] : nil
    }

    /// "Speichern" for "Speicher", "liefert" for "liefern", "battery" for
    /// "batteries": long words with the same first letter and at most one
    /// changed letter (two from ten), or a shared stem with a different ending.
    static func isNearMiss(_ heard: String, of script: String) -> Bool {
        guard heard != script, heard.count >= 6, script.count >= 6, heard.first == script.first else { return false }
        let shorter = min(heard.count, script.count)
        let stem = zip(heard, script).prefix(while: { $0 == $1 }).count
        if stem >= 5, stem >= shorter - 2, abs(heard.count - script.count) <= 3 { return true }
        return editDistance(heard, script, limit: shorter >= 10 ? 2 : 1) != nil
    }
}
