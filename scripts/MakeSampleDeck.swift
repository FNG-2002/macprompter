// Generates the bundled example presentation for the template library.
//   swift scripts/MakeSampleDeck.swift
// 10 slides; slide 3 reveals three points in three steps (12 PDF pages).
import AppKit
import CoreText

let size = CGSize(width: 960, height: 540)
let background = CGColor(red: 0.075, green: 0.08, blue: 0.10, alpha: 1)
let accent = NSColor(red: 0.72, green: 0.67, blue: 1, alpha: 1)
let soft = NSColor(white: 1, alpha: 0.62)
let url = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "MacPrompter/Resources/Templates/Beispiel-Praesentation.pdf")

var box = CGRect(origin: .zero, size: size)
guard let context = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "Quartalsupdate Q3"] as CFDictionary) else { fatalError("cannot create PDF") }

func text(_ string: String, _ point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white, width: CGFloat = 820) {
    let attributed = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    let setter = CTFramesetterCreateWithAttributedString(attributed)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: point.x, y: point.y - fit.height, width: width, height: fit.height), transform: nil), nil)
    CTFrameDraw(frame, context)
}

func page(number: Int, eyebrow: String, title: String, _ content: () -> Void = {}) {
    context.beginPDFPage(nil)
    context.setFillColor(background); context.fill(box)
    context.setFillColor(accent.cgColor); context.fill(CGRect(x: 70, y: 452, width: 36, height: 4))
    text(eyebrow.uppercased(), CGPoint(x: 70, y: 440), size: 13, weight: .semibold, color: accent)
    text(title, CGPoint(x: 70, y: 412), size: 40, weight: .bold)
    content()
    text("Team Nordlicht · Quartalsupdate Q3", CGPoint(x: 70, y: 44), size: 11, color: NSColor(white: 1, alpha: 0.35))
    text("\(number)", CGPoint(x: 870, y: 44), size: 11, weight: .semibold, color: NSColor(white: 1, alpha: 0.35), width: 20)
    context.endPDFPage()
}

func bullet(_ index: Int, _ title: String, _ detail: String, y: CGFloat, visible: Bool = true) {
    guard visible else { return }
    let alpha: CGFloat = 1
    context.setFillColor(accent.withAlphaComponent(alpha).cgColor)
    context.fillEllipse(in: CGRect(x: 70, y: y - 40, width: 44, height: 44))
    text("\(index)", CGPoint(x: 85, y: y - 7), size: 20, weight: .bold, color: NSColor(white: 0.08, alpha: alpha))
    text(title, CGPoint(x: 134, y: y - 2), size: 24, weight: .semibold, color: NSColor(white: 1, alpha: alpha))
    text(detail, CGPoint(x: 134, y: y - 34), size: 16, color: soft.withAlphaComponent(0.62 * alpha))
}

func bars(_ values: [(String, CGFloat)]) {
    for (index, (label, value)) in values.enumerated() {
        let x = 110 + CGFloat(index) * 190
        context.setFillColor(index == values.count - 1 ? accent.cgColor : NSColor(white: 1, alpha: 0.18).cgColor)
        context.fill(CGRect(x: x, y: 110, width: 110, height: value * 1.6))
        text(label, CGPoint(x: x, y: 100), size: 14, color: soft, width: 140)
        text("\(Int(value)) T€", CGPoint(x: x, y: 110 + value * 1.6 + 28), size: 16, weight: .semibold, width: 140)
    }
}

// 1
context.beginPDFPage(nil)
context.setFillColor(background); context.fill(box)
context.setFillColor(accent.cgColor); context.fill(CGRect(x: 70, y: 330, width: 48, height: 5))
text("Quartalsupdate Q3", CGPoint(x: 70, y: 310), size: 58, weight: .bold)
text("Team Nordlicht · Oktober 2026", CGPoint(x: 70, y: 226), size: 22, color: soft)
context.endPDFPage()
// 2
page(number: 2, eyebrow: "Agenda", title: "Worum es heute geht") {
    for (index, item) in ["Rückblick auf das Quartal", "Drei Schwerpunkte", "Zahlen und Kundenstimmen", "Ausblick auf Q4"].enumerated() {
        text("\(index + 1)   \(item)", CGPoint(x: 70, y: 330 - CGFloat(index) * 52), size: 26, color: index == 1 ? accent : .white)
    }
}
// 3 – three reveal steps on three PDF pages
for step in 0..<3 {
    page(number: 3, eyebrow: "Schwerpunkte", title: "Drei Dinge, die wir angepackt haben") {
        bullet(1, "Kundenfeedback ernst nehmen", "Jede Woche fünf Gespräche mit Kundinnen und Kunden", y: 330)
        bullet(2, "Schneller ausliefern", "Kleinere Releases, automatische Tests", y: 250, visible: step >= 1)
        bullet(3, "Neue Märkte", "Start in Österreich und der Schweiz", y: 170, visible: step >= 2)
    }
}
// 4
page(number: 4, eyebrow: "Kundenstimmen", title: "Zufriedenheit") {
    text("92 %", CGPoint(x: 70, y: 330), size: 120, weight: .heavy, color: accent)
    text("würden uns weiterempfehlen – plus 7 Punkte gegenüber Q2", CGPoint(x: 70, y: 170), size: 24, color: soft)
}
// 5
page(number: 5, eyebrow: "Zahlen", title: "Umsatz pro Monat") { bars([("Juli", 96), ("August", 104), ("September", 121)]) }
// 6
page(number: 6, eyebrow: "Tempo", title: "Von der Idee bis zum Release") {
    text("14 Tage", CGPoint(x: 70, y: 310), size: 64, weight: .bold, color: NSColor(white: 1, alpha: 0.35))
    text("→", CGPoint(x: 360, y: 310), size: 64, weight: .bold, color: soft)
    text("6 Tage", CGPoint(x: 470, y: 310), size: 64, weight: .bold, color: accent)
    text("Durchschnittliche Zeit bis zur Auslieferung", CGPoint(x: 70, y: 190), size: 22, color: soft)
}
// 7
page(number: 7, eyebrow: "Wachstum", title: "Neue Märkte") {
    text("Österreich", CGPoint(x: 70, y: 320), size: 36, weight: .semibold)
    text("seit August · 38 Kunden", CGPoint(x: 70, y: 274), size: 20, color: soft)
    text("Schweiz", CGPoint(x: 500, y: 320), size: 36, weight: .semibold)
    text("seit September · 12 Kunden", CGPoint(x: 500, y: 274), size: 20, color: soft)
}
// 8
page(number: 8, eyebrow: "Learnings", title: "Was wir mitnehmen") {
    for (index, item) in ["Früh testen spart später Zeit", "Feedback braucht feste Termine", "Weniger parallel, mehr fertig"].enumerated() {
        text("—  \(item)", CGPoint(x: 70, y: 320 - CGFloat(index) * 56), size: 26)
    }
}
// 9
page(number: 9, eyebrow: "Ausblick", title: "Unsere Ziele für Q4") {
    for (index, item) in ["Release 3.0 im November", "100 Kunden in neuen Märkten", "Zufriedenheit über 93 %"].enumerated() {
        text("\(index + 1)   \(item)", CGPoint(x: 70, y: 320 - CGFloat(index) * 56), size: 26)
    }
}
// 10
context.beginPDFPage(nil)
context.setFillColor(background); context.fill(box)
text("Danke!", CGPoint(x: 70, y: 330), size: 72, weight: .bold)
text("Fragen und Ideen sind willkommen.", CGPoint(x: 70, y: 220), size: 24, color: accent)
context.endPDFPage()

context.closePDF()
print("Wrote \(url.path)")
