import Foundation

/// Text for one slide of a template deck; `pages` > 1 reveals the slide in steps.
struct TemplateSlide: Sendable {
    let pages: Int
    let text: String
}

/// Example scripts the user can copy into the library as a starting point.
struct ScriptTemplate: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let language: SpeechLanguage
    var body = ""
    var pdfResource: String?
    var slides: [TemplateSlide] = []

    var isPresentation: Bool { pdfResource != nil }
    var preview: String { isPresentation ? slides.map(\.text).joined(separator: "\n\n") : body }
    var details: String {
        let words = ScriptParser.words(in: preview).count
        if isPresentation {
            return "\(slides.count) Folien · \(slides.reduce(0) { $0 + $1.pages }) PDF-Seiten · \(words) Wörter"
        }
        return "\(language.shortTitle) · \(words) Wörter"
    }

    static let all = [firstTake, introduction, presentation]

    static let firstTake = ScriptTemplate(id: "first-take", title: Script.welcome.title,
        summary: "Kurzer Einstieg mit Regieanweisungen – ideal, um Stimme, Tempo und Hover-Pause auszuprobieren.",
        symbol: "video", language: .german, body: Script.welcome.body)

    static let introduction = ScriptTemplate(id: "introduction", title: Script.english.title,
        summary: "Eine englische Vorstellung für Videos und Calls, mit Sprachsteuerung auf Englisch.",
        symbol: "person.wave.2", language: .english, body: Script.english.body)

    static let presentation = ScriptTemplate(id: "presentation", title: "Quartalsupdate in 10 Folien",
        summary: "Präsentation mit PDF: Folie 3 deckt drei Punkte nacheinander auf und bleibt trotzdem eine Folie.",
        symbol: "rectangle.on.rectangle", language: .german, pdfResource: "Beispiel-Praesentation", slides: [
            TemplateSlide(pages: 1, text: "Herzlich willkommen zu unserem Quartalsupdate. [Lächeln] Ich nehme euch in den nächsten Minuten mit durch das dritte Quartal."),
            TemplateSlide(pages: 1, text: "Wir schauen kurz zurück, dann auf drei Schwerpunkte, danach auf Zahlen und Kundenstimmen. Zum Schluss geht es um unsere Ziele für das vierte Quartal."),
            TemplateSlide(pages: 3, text: "Drei Dinge haben wir uns vorgenommen. Erstens hören wir unseren Kundinnen und Kunden zu, jede Woche in fünf Gesprächen.\n[Weiter]\nZweitens liefern wir schneller aus, mit kleineren Releases und automatischen Tests.\n[Weiter]\nUnd drittens sind wir in zwei neue Märkte gestartet."),
            TemplateSlide(pages: 1, text: "Das Ergebnis sieht man bei der Zufriedenheit. Zweiundneunzig Prozent würden uns weiterempfehlen. [Pause] Das sind sieben Punkte mehr als im Sommer."),
            TemplateSlide(pages: 1, text: "Auch der Umsatz ist jeden Monat gewachsen. Im September lagen wir zum ersten Mal über hundertzwanzigtausend Euro."),
            TemplateSlide(pages: 1, text: "Besonders stolz sind wir auf unser Tempo. Früher hat es vierzehn Tage gedauert, bis eine Idee bei unseren Kunden ankam. Heute sind es sechs."),
            TemplateSlide(pages: 1, text: "Seit August sind wir in Österreich, seit September in der Schweiz. Zusammen haben wir dort schon fünfzig Kunden gewonnen."),
            TemplateSlide(pages: 1, text: "Was nehmen wir mit? Früh testen spart später Zeit. Feedback braucht feste Termine. Und lieber weniger parallel, dafür mehr fertig."),
            TemplateSlide(pages: 1, text: "Für das vierte Quartal haben wir drei Ziele: Release drei im November, hundert Kunden in den neuen Märkten und eine Zufriedenheit von über dreiundneunzig Prozent."),
            TemplateSlide(pages: 1, text: "Vielen Dank fürs Zuhören. [Pause] Ich freue mich auf eure Fragen und Ideen."),
        ])
}

extension PresentationDeck {
    /// Rebuilds the sections from a template; returns false if the page count does not match.
    @discardableResult
    mutating func apply(_ slides: [TemplateSlide]) -> Bool {
        guard slides.reduce(0, { $0 + $1.pages }) == pages.count else { return false }
        var next = 0
        sections = slides.map { slide in
            defer { next += slide.pages }
            return SlideSection(pageIDs: pages[next..<next + slide.pages].map(\.id), text: slide.text)
        }
        return true
    }
}
