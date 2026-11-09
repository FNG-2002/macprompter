import XCTest
import SwiftUI
@testable import MacPrompter

@MainActor
final class TemplateTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFreshLibraryStartsEmpty() throws {
        let library = ScriptLibrary(directory: try folder())
        XCTAssertTrue(library.scripts.isEmpty)
        XCTAssertNil(library.selectedID)
    }

    func testAtLeastThreeTemplatesIncludingRevealedSlide() {
        XCTAssertGreaterThanOrEqual(ScriptTemplate.all.count, 3)
        XCTAssertEqual(ScriptTemplate.firstTake.body, Script.welcome.body)
        XCTAssertEqual(ScriptTemplate.introduction.language, .english)
        let deck = ScriptTemplate.presentation
        XCTAssertEqual(deck.slides.count, 10)
        XCTAssertEqual(deck.slides[2].pages, 3)
        XCTAssertEqual(deck.slides[2].text.components(separatedBy: "[Weiter]").count, 3)
    }

    func testPresentationTemplateBuildsTenSlidesWithSteps() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Beispiel-Praesentation", withExtension: "pdf"))
        let files = PresentationFiles(folder: try folder())
        var deck = try await files.makeDeck(from: url)
        XCTAssertEqual(deck.pages.count, 12)
        XCTAssertTrue(deck.apply(ScriptTemplate.presentation.slides))
        XCTAssertEqual(deck.sections.count, 10)
        XCTAssertEqual(deck.pageIndices(of: deck.sections[2]), [2, 3, 4])

        let (body, timeline) = PresentationComposer.compose(deck)
        XCTAssertTrue(body.contains("[Start · Folie 3 · 3 Schritte]"))
        XCTAssertTrue(body.contains("[Start · Folie 4]"))
        XCTAssertEqual(timeline.slideCount, 10)
        let ns = body as NSString
        XCTAssertEqual(timeline.page(at: ns.range(of: "Zweitens").location), 3)
        XCTAssertEqual(timeline.page(at: ns.range(of: "drittens").location), 4)

        let status = SlideStatus(current: 3, count: 12, position: timeline.positions[3], slideCount: timeline.slideCount)
        XCTAssertEqual(status.label, "Folie 3 von 10 · Schritt 2/3")
        XCTAssertEqual(SlideStatus(current: 9, count: 12, position: timeline.positions[9], slideCount: 10).label, "Folie 8 von 10")

        var short = deck
        XCTAssertFalse(short.apply(Array(ScriptTemplate.presentation.slides.dropLast())))
        short = deck
        XCTAssertEqual(short.sections.count, 10)
    }

    func testStoredPresentationBodyIsRefreshedOnLoad() throws {
        let directory = try folder()
        var deck = PresentationDeck(fileName: "x.pdf", pages: [SlidePage(text: "a", imageHash: 0), SlidePage(text: "b", imageHash: 1)])
        deck.groupWithNext(deck.sections[0].id)
        var script = Script(title: "Alt", body: "[Start · Folien 1–2]\n[Ende der Präsentation]")
        script.presentation = deck
        try JSONEncoder().encode([script]).write(to: directory.appending(path: "scripts.json"))
        let library = ScriptLibrary(directory: directory)
        XCTAssertEqual(library.scripts.first?.body, PresentationComposer.compose(deck).body)
        XCTAssertTrue(library.scripts.first?.body.hasPrefix("[Start · Folie 1 · 2 Schritte]") == true)
    }

    func testRemoteSlideLabelFallsBackToPages() {
        XCTAssertEqual(RemoteSlides(current: 4, count: 12, isPresenting: true).label, "Folie 5 von 12")
        XCTAssertEqual(RemoteSlides(current: 4, count: 12, isPresenting: true, slide: 2, slideCount: 10, step: 2, steps: 3).label,
                       "Folie 3 von 10 · Schritt 3/3")
    }

    func testGalleryAndTemplateEditorRender() async throws {
        let model = AppModel.shared
        let files = model.presentationFiles
        model.presentationFiles = PresentationFiles(folder: try folder())
        defer { model.presentationFiles = files }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Beispiel-Praesentation", withExtension: "pdf"))
        var deck = try await model.presentationFiles.makeDeck(from: url)
        deck.apply(ScriptTemplate.presentation.slides)
        var script = Script(title: ScriptTemplate.presentation.title, body: "")
        script.presentation = deck
        script.body = PresentationComposer.compose(deck).body
        for (name, view, size) in [("templates", AnyView(TemplateGallery(model: model)), CGSize(width: 760, height: 560)),
                                   ("template-editor", AnyView(SlideEditorView(model: model, script: script, deck: deck).background(Design.canvas)), CGSize(width: 760, height: 900))] {
            let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 1000)
            try data.write(to: FileManager.default.temporaryDirectory.appending(path: "macprompter-\(name).png"))
        }
    }
}
