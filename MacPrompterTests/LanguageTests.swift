import XCTest
@testable import MacPrompter

final class LanguageTests: XCTestCase {
    func testLanguagesFromVersionOneDecodeUnchanged() throws {
        let json = #"[{"id":"9B3F1C2E-0000-4000-8000-000000000001","title":"A","body":"Hallo","modifiedAt":0,"language":"en-US"}]"#
        let scripts = try JSONDecoder().decode([Script].self, from: Data(json.utf8))
        XCTAssertEqual(scripts.first?.language, .english)
        var turkish = Script(title: "T", body: "Merhaba")
        turkish.language = SpeechLanguage(rawValue: "tr_TR")
        let data = try JSONEncoder().encode(turkish)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""language":"tr-TR""#))
        XCTAssertEqual(try JSONDecoder().decode(Script.self, from: data).language.rawValue, "tr-TR")
    }

    func testCodesMapToTheUsualLocale() {
        XCTAssertEqual(SpeechLanguage(code: "de"), .german)
        XCTAssertEqual(SpeechLanguage(code: "en"), .english)
        XCTAssertEqual(SpeechLanguage(code: "fr")?.rawValue, "fr-FR")
        XCTAssertEqual(SpeechLanguage(code: "tr")?.rawValue, "tr-TR")
        XCTAssertEqual(SpeechLanguage(code: "de_CH")?.rawValue, "de-CH")
        XCTAssertNil(SpeechLanguage(code: ""))
        XCTAssertNil(SpeechLanguage(code: "de; rm"))
        XCTAssertEqual(SpeechLanguage.german.shortCode, "de")
        XCTAssertEqual(SpeechLanguage(rawValue: "de-CH").shortCode, "de-CH")
        XCTAssertEqual(SpeechLanguage(rawValue: "tr-TR").title, "Türkisch (Türkei)")
        XCTAssertFalse(SpeechLanguage(rawValue: "ja-JP").separatesWords)
        XCTAssertTrue(SpeechLanguage(rawValue: "ko-KR").separatesWords)
    }

    func testSuggestsTheScriptsLanguageOnlyWhenClear() {
        let candidates = ["de-DE", "de-CH", "en-US", "en-GB", "tr-TR", "fr-FR", "fr-CA"].map(SpeechLanguage.init(rawValue:))
        let turkish = "Merhaba arkadaşlar. Bugün size yeni projemizi anlatmak istiyorum. [Gülümse] Bu uygulama tamamen bilgisayarınızda çalışıyor ve sesinizi takip ediyor."
        XCTAssertEqual(SpeechLanguage.suggestion(for: turkish, current: .german, among: candidates)?.rawValue, "tr-TR")
        let french = "Bonjour à tous. Aujourd'hui je voudrais vous présenter notre nouveau projet et vous expliquer pourquoi il est important pour nous."
        XCTAssertEqual(SpeechLanguage.suggestion(for: french, current: .german, among: candidates)?.rawValue, "fr-FR")
        XCTAssertNil(SpeechLanguage.suggestion(for: Script.welcome.body, current: .german, among: candidates), "already the right language")
        XCTAssertNil(SpeechLanguage.suggestion(for: Script.welcome.body, current: SpeechLanguage(rawValue: "de-CH"), among: candidates), "a regional variant is kept")
        XCTAssertEqual(SpeechLanguage.suggestion(for: Script.english.body, current: .german, among: candidates)?.rawValue, "en-US")
        XCTAssertNil(SpeechLanguage.suggestion(for: "Hallo Welt", current: .english, among: candidates), "too short to tell")
        XCTAssertNil(SpeechLanguage.suggestion(for: turkish, current: .german, among: [.german, .english]), "not offered on this Mac")
    }

    func testCombiningMarksStayInsideWords() {
        let decomposed = "Herr Mu\u{0308}ller spricht"
        let words = ScriptParser.words(in: decomposed).map(\.normalized)
        XCTAssertEqual(words, ScriptParser.words(in: "Herr Müller spricht").map(\.normalized))
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(ScriptParser.words(in: "नमस्ते दोस्तों").count, 2, "Hindi vowel signs are combining marks")
        XCTAssertEqual(ScriptParser.words(in: "Don’t stop, it's fine").map(\.normalized), ["don't", "stop", "it's", "fine"])
    }

    func testTextColourIsOptionalInStoredPreferences() throws {
        var stored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
        XCTAssertEqual(stored.textColor, .white)
        stored.textColor = .green; stored.font = .serif
        var settings = stored.scriptSettings
        XCTAssertEqual(settings.textColor, .green)
        settings = try JSONDecoder().decode(ScriptSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings.textColor, .green)
        XCTAssertEqual(settings.font, .serif)
        let old = try JSONDecoder().decode(ScriptSettings.self, from: Data(#"{"font":"system","fontSize":30}"#.utf8))
        XCTAssertEqual(old.textColor, .white)
    }
}
