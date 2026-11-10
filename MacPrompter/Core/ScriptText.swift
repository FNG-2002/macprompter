import Foundation
import NaturalLanguage

/// Kept free of app types so the alignment can be built and benchmarked
/// with swiftc alone (see scripts/Benchmark*.swift).
///
/// A recognition locale as BCP 47 identifier ("de-DE", "tr-TR"). Encoded as
/// a plain string, so libraries from 1.0 ("de-DE", "en-US") decode unchanged.
struct SpeechLanguage: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue.replacingOccurrences(of: "_", with: "-") }
    init(from decoder: any Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    static let german = SpeechLanguage(rawValue: "de-DE")
    static let english = SpeechLanguage(rawValue: "en-US")
    var id: String { rawValue }
    /// Language without region, e.g. "de".
    var code: String { String(rawValue.prefix { $0 != "-" }).lowercased() }
    /// With region, for choosing between variants: "Deutsch (Schweiz)".
    var title: String {
        Self.uiLocale.localizedString(forIdentifier: rawValue) ?? shortTitle
    }
    /// Language only, region only for uncommon variants: "Deutsch", "Deutsch (Schweiz)".
    var shortTitle: String {
        guard SpeechLanguage(code: code) == self else { return title }
        return Self.uiLocale.localizedString(forLanguageCode: code) ?? rawValue
    }
    private static let uiLocale = Locale(identifier: "de_DE")

    /// The usual locale for a language code or identifier: "fr" → "fr-FR",
    /// "en" → "en-US", "pt" → "pt-BR"; full identifiers stay as they are.
    init?(code: String) {
        let value = code.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-")
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else { return nil }
        let language = Locale.Language(identifier: value)
        guard let code = language.languageCode?.identifier else { return nil }
        let region = language.region ?? Locale.Language(identifier: language.maximalIdentifier).region
        self.init(rawValue: region.map { "\(code)-\($0.identifier)" } ?? code)
    }

    /// Shortest form that maps back to this locale: "de" for de-DE, "de-CH" otherwise.
    var shortCode: String { SpeechLanguage(code: code) == self ? code : rawValue }

    /// Writing systems without spaces between words. The alignment works on
    /// space-separated words, so these languages are not offered.
    static let unsegmentedLanguages: Set<String> = ["ja", "zh", "yue", "th", "lo", "km", "my"]
    var separatesWords: Bool { !Self.unsegmentedLanguages.contains(code) }

    /// A language the script is clearly written in, if it differs from `current`.
    /// Picks the candidate with the language's usual region, then the user's region.
    static func suggestion(for text: String, current: SpeechLanguage, among candidates: [SpeechLanguage]) -> SpeechLanguage? {
        let spoken = text.replacingOccurrences(of: #"\[[^\]\n]*\]"#, with: " ", options: .regularExpression)
        let sample = String(spoken.prefix(6000))
        guard sample.lazy.filter(\.isLetter).prefix(40).count == 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined,
              let confidence = recognizer.languageHypotheses(withMaximum: 2)[dominant], confidence >= 0.8 else { return nil }
        let code = Locale.Language(identifier: dominant.rawValue).languageCode?.identifier ?? dominant.rawValue
        guard code != current.code else { return nil }
        let matching = candidates.filter { $0.code == code }
        let regional = Locale.current.region.map { SpeechLanguage(rawValue: "\(code)-\($0.identifier)") }
        return matching.first { $0 == SpeechLanguage(code: code) }
            ?? matching.first { $0 == regional }
            ?? matching.first
    }
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
        // Combining marks belong to the word: Hindi vowel signs, and umlauts
        // from decomposed (NFD) text such as pasted file names.
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{M}\p{N}]*(?:['’][\p{L}\p{N}][\p{L}\p{M}\p{N}]*)*"#)
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
