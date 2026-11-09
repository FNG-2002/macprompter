import Foundation

/// Kept free of app types so the alignment can be built and benchmarked
/// with swiftc alone (see scripts/Benchmark*.swift).
enum SpeechLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case german = "de-DE", english = "en-US"
    var id: String { rawValue }
    var title: String { self == .german ? "Deutsch" : "English" }
}

struct ScriptToken: Equatable {
    let normalized: String
    let range: NSRange
}

enum ScriptParser {
    static func cueRanges(in text: String) -> [NSRange] {
        let regex = try! NSRegularExpression(pattern: #"\[[^\]\n]+\]"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    static func words(in text: String) -> [ScriptToken] {
        let cues = cueRanges(in: text)
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard !cues.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
            return ScriptToken(normalized: normalize(ns.substring(with: match.range)), range: match.range)
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss").replacingOccurrences(of: "’", with: "'")
    }

    /// Distinct spoken words as written, longest first: contextual strings
    /// for the dictation recognizer. Names and terms are rarely short.
    static func vocabulary(in text: String, limit: Int = 2000) -> [String] {
        let ns = text as NSString
        var seen = Set<String>(), result: [String] = []
        for token in words(in: text) where token.range.length >= 3 {
            let word = ns.substring(with: token.range)
            if seen.insert(word).inserted { result.append(word) }
        }
        return Array(result.enumerated().sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }.map(\.element).prefix(limit))
    }
}
