import XCTest
import AppKit
import PDFKit
import SwiftUI
@testable import MacPrompter

private func page(_ text: String, hash: UInt64 = 0) -> SlidePage {
    SlidePage(text: ScriptParser.normalize(text), imageHash: hash)
}

private func deck(_ texts: [String], spoken: [String]) -> PresentationDeck {
    var deck = PresentationDeck(fileName: "Talk.pdf", pages: texts.map { page($0) })
    for (index, text) in spoken.enumerated() { deck.sections[index].text = text }
    return deck
}

final class PresentationComposerTests: XCTestCase {
    func testEverySlideStartsAndEndsWithCues() {
        let deck = deck(["Titel", "Agenda", "Danke"], spoken: ["Hallo zusammen.", "Heute drei Punkte.", "Vielen Dank."])
        let (body, timeline) = PresentationComposer.compose(deck)
        XCTAssertEqual(body, """
        [Start · Folie 1]
        Hallo zusammen.
        [Nächste Folie]

        [Start · Folie 2]
        Heute drei Punkte.
        [Nächste Folie]

        [Start · Folie 3]
        Vielen Dank.
        [Ende der Präsentation]
        """)
        XCTAssertEqual(ScriptParser.words(in: body).map(\.normalized), ["hallo", "zusammen", "heute", "drei", "punkte", "vielen", "dank"])
        XCTAssertEqual(timeline.pageCount, 3)
        let ns = body as NSString
        XCTAssertEqual(timeline.page(at: 0), 0)
        XCTAssertEqual(timeline.page(at: ns.range(of: "zusammen").location), 0)
        // The "Nächste Folie" cue switches; the following start cue is the jump anchor.
        XCTAssertEqual(timeline.page(at: ns.range(of: "[Nächste Folie]").location), 1)
        XCTAssertEqual(timeline.page(at: ns.range(of: "Heute").location), 1)
        XCTAssertEqual(timeline.page(at: ns.range(of: "Vielen").location), 2)
        XCTAssertEqual(timeline.anchor(forPage: 1), ns.range(of: "[Start · Folie 2]").location)
    }

    func testGroupAdvancesAtWeiterCueOrEvenlyByWords() {
        var explicit = deck(["A", "B", "C"], spoken: ["Erst das. [Weiter] Dann das.", "", "Schluss."])
        explicit.groupWithNext(explicit.sections[0].id)
        let (body, timeline) = PresentationComposer.compose(explicit)
        let ns = body as NSString
        XCTAssertTrue(body.hasPrefix("[Start · Folie 1 · 2 Schritte]\n"))
        XCTAssertTrue(body.contains("[Start · Folie 2]\nSchluss."))
        XCTAssertEqual(timeline.page(at: ns.range(of: "das").location), 0)
        XCTAssertEqual(timeline.page(at: ns.range(of: "Dann").location), 1)
        XCTAssertEqual(timeline.page(at: ns.range(of: "Schluss").location), 2)

        var even = deck(["A", "B", "C"], spoken: ["eins zwei drei vier fünf sechs"])
        even.groupWithNext(even.sections[0].id)
        even.groupWithNext(even.sections[0].id)
        let evenly = PresentationComposer.compose(even)
        let text = evenly.body as NSString
        XCTAssertEqual(evenly.timeline.page(at: text.range(of: "zwei").location), 0)
        XCTAssertEqual(evenly.timeline.page(at: text.range(of: "drei").location), 1)
        XCTAssertEqual(evenly.timeline.page(at: text.range(of: "fünf").location), 2)
    }

    func testUngroupKeepsTextOnFirstPage() {
        var deck = deck(["A", "B"], spoken: ["Text A", "Text B"])
        deck.groupWithNext(deck.sections[0].id)
        XCTAssertEqual(deck.sections.count, 1)
        XCTAssertEqual(deck.sections[0].text, "Text A\n\nText B")
        deck.ungroup(deck.sections[0].id)
        XCTAssertEqual(deck.sections.map(\.text), ["Text A\n\nText B", ""])
        XCTAssertEqual(deck.sections.map(\.pageIDs), deck.pages.map { [$0.id] })
    }
}

final class SlideMatcherTests: XCTestCase {
    private let texts = ["Willkommen beim Quartalsbericht", "Umsatz wächst um zwölf Prozent", "Ausblick und nächste Schritte"]

    func testInsertedPageGetsOwnEmptySectionWithoutReordering() {
        var deck = deck(texts, spoken: ["Hallo", "Zahlen", "Ausblick"])
        let change = deck.adopt(pages: [page(texts[0]), page("Neue Kundenumfrage mit Ergebnissen"), page(texts[1]), page(texts[2])])
        XCTAssertEqual(change, PresentationChange(added: 1, removed: 0, changed: 0))
        XCTAssertEqual(deck.sections.map(\.text), ["Hallo", "", "Zahlen", "Ausblick"])
        XCTAssertEqual(deck.sections.map { deck.pageIndices(of: $0) }, [[0], [1], [2], [3]])
        XCTAssertEqual(deck.pages[1].flag, .added)
    }

    func testRemovedPageKeepsItsTextInPlace() {
        var deck = deck(texts, spoken: ["Hallo", "Zahlen", "Ausblick"])
        let change = deck.adopt(pages: [page(texts[0]), page(texts[2])])
        XCTAssertEqual(change.removed, 1)
        XCTAssertEqual(deck.sections.map(\.text), ["Hallo", "Zahlen", "Ausblick"])
        XCTAssertTrue(deck.sections[1].pageIDs.isEmpty)
        XCTAssertTrue(deck.hasFlags)
        let (body, timeline) = PresentationComposer.compose(deck)
        XCTAssertTrue(body.contains("[Ohne Folie]\nZahlen"))
        XCTAssertEqual(timeline.page(at: (body as NSString).range(of: "Zahlen").location), 0)
        deck.removeOrphan(deck.sections[1].id)
        XCTAssertEqual(deck.sections.map(\.text), ["Hallo", "Ausblick"])
    }

    func testReorderedPagesTakeTheirTextAlong() {
        var deck = deck(texts, spoken: ["Hallo", "Zahlen", "Ausblick"])
        deck.adopt(pages: [page(texts[2]), page(texts[0]), page(texts[1])])
        XCTAssertEqual(deck.sections.map(\.text), ["Ausblick", "Hallo", "Zahlen"])
    }

    func testSlightlyEditedAndRewrittenPagesKeepTheirText() {
        var deck = deck(texts, spoken: ["Hallo", "Zahlen", "Ausblick"])
        let change = deck.adopt(pages: [page("Willkommen beim Quartalsbericht 2026"), page("Komplett neue Grafik"), page(texts[2])])
        XCTAssertEqual(change, PresentationChange(added: 0, removed: 0, changed: 1))
        XCTAssertEqual(deck.sections.map(\.text), ["Hallo", "Zahlen", "Ausblick"])
        XCTAssertNil(deck.pages[0].flag)
        XCTAssertEqual(deck.pages[1].flag, .changed)
    }

    func testPageInsertedIntoGroupJoinsTheGroup() {
        var deck = deck(texts, spoken: ["Hallo", "Zahlen in zwei Schritten", "Ausblick"])
        deck.groupWithNext(deck.sections[1].id)
        deck.adopt(pages: [page(texts[0]), page(texts[1]), page("Zwischenschritt der Animation"), page(texts[2])])
        XCTAssertEqual(deck.sections.count, 2)
        XCTAssertEqual(deck.pageIndices(of: deck.sections[1]), [1, 2, 3])
    }

    func testImageOnlyPagesMatchByHashAndStayOrdered() {
        let photo: UInt64 = 0xF0F0_F0F0_0F0F_0F0F, chart: UInt64 = 0x1234_5678_9ABC_DEF0
        var deck = PresentationDeck(fileName: "x.pdf", pages: [page("", hash: photo), page("", hash: chart)])
        deck.sections[0].text = "Foto"; deck.sections[1].text = "Diagramm"
        // Re-export flips a few bits; a new blank page appears first.
        deck.adopt(pages: [page("", hash: 0), page("", hash: photo ^ 0b101), page("", hash: chart ^ 0b1)])
        XCTAssertEqual(deck.sections.map(\.text), ["", "Foto", "Diagramm"])
    }

    func testIdenticalPagesAreMatchedInOrder() {
        var deck = deck(["Kapitel", "Kapitel"], spoken: ["Erstes", "Zweites"])
        let change = deck.adopt(pages: [page("Kapitel"), page("Kapitel"), page("Kapitel")])
        XCTAssertEqual(change.added, 1)
        XCTAssertEqual(deck.sections.map(\.text), ["Erstes", "Zweites", ""])
    }
}

final class PresentationPersistenceTests: XCTestCase {
    func testLibraryWithoutPresentationStillDecodes() throws {
        let json = #"[{"id":"7C3A3A4E-55B5-4C6B-9D33-2D1D1E9B8F10","title":"Alt","body":"Hallo","modifiedAt":0,"language":"de-DE"}]"#
        let scripts = try JSONDecoder().decode([Script].self, from: Data(json.utf8))
        XCTAssertNil(scripts[0].presentation)
        var script = scripts[0]
        script.presentation = deck(["A"], spoken: ["Hallo"])
        let restored = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(script))
        XCTAssertEqual(restored, script)
    }

    func testOlderPreferencesKeepPresentationDefaults() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
        XCTAssertEqual(decoded.presentationDisplayID, 0)
        XCTAssertTrue(decoded.presenterView)
        let legacy = #"{"mode":"voice","font":"system","fontSize":30,"lineSpacing":12,"speed":36,"width":620,"height":300,"countdownSeconds":3,"mirror":false,"focusLine":true,"docked":true,"displayID":0,"reduceMotion":false}"#
        let old = try JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.fontSize, 30)
        XCTAssertTrue(old.presenterView)
    }

    @MainActor func testLibraryDerivesBodyAndDetachKeepsText() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ScriptLibrary(directory: folder)
        library.add(title: "Talk", presentation: deck(["A", "B"], spoken: ["Eins", "Zwei"]))
        let id = try XCTUnwrap(library.selectedID)
        XCTAssertTrue(library.selected?.body.contains("[Start · Folie 2]\nZwei") == true)
        var changed = try XCTUnwrap(library.selected?.presentation)
        changed.setText("Drei", section: changed.sections[1].id)
        library.updatePresentation(changed, for: id)
        XCTAssertTrue(library.selected?.body.contains("Drei\n[Ende der Präsentation]") == true)
        library.updatePresentation(nil, for: id)
        XCTAssertEqual(library.selected?.body, "Eins\n\nDrei")
        XCTAssertNil(library.selected?.presentation)
    }
}

@MainActor
final class PresentationSessionTests: XCTestCase {
    private func makeSession(mode: PlaybackMode, spoken: [String] = ["Hallo zusammen heute", "Unsere Zahlen steigen deutlich", "Vielen Dank fürs Zuhören"]) -> PrompterSession {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = mode
        let session = PrompterSession(preferences: preferences)
        var script = Script(title: "Talk", body: "")
        script.presentation = deck(["A", "B", "C"], spoken: spoken)
        script.body = PresentationComposer.compose(script.presentation!).body
        session.script = script
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        session.systemReducesMotion = { false }
        return session
    }

    func testVoiceSwitchesSlideAfterLastWordOfSection() {
        let session = makeSession(mode: .voice)
        XCTAssertEqual(session.slideStatus, SlideStatus(current: 0, count: 3))
        session.receiveTranscript("Hallo zusammen", segment: 0, endTime: 1)
        XCTAssertEqual(session.currentSlide, 0)
        session.receiveTranscript("Hallo zusammen heute", segment: 0, endTime: 2)
        XCTAssertEqual(session.currentSlide, 1)
        session.receiveTranscript("Unsere Zahlen steigen", segment: 1, endTime: 3)
        XCTAssertEqual(session.currentSlide, 1)
        session.hide()
    }

    func testHoverBlocksSpokenSlideChanges() {
        let session = makeSession(mode: .voice)
        session.setHover(true)
        session.receiveTranscript("Hallo zusammen heute", segment: 0, endTime: 1)
        XCTAssertEqual(session.currentSlide, 0)
        session.hide()
    }

    func testManualSlideJumpsTextUnlessHovering() {
        let session = makeSession(mode: .voice)
        session.maximumOffset = 1000
        session.stepSlide(1)
        XCTAssertEqual(session.currentSlide, 1)
        let anchor = session.slideTimeline?.anchor(forPage: 1)
        XCTAssertEqual(session.jumpCharacter, anchor)
        session.resolveJump(240, for: anchor!)
        XCTAssertEqual(session.offset, 240)
        XCTAssertNil(session.jumpCharacter)
        // Voice continues from the chosen slide: its first word matches locally.
        session.receiveTranscript("Unsere Zahlen steigen deutlich", segment: 4, endTime: 5)
        XCTAssertEqual(session.currentSlide, 2)

        session.setHover(true)
        session.stepSlide(-1)
        XCTAssertEqual(session.currentSlide, 1)
        XCTAssertNil(session.jumpCharacter)
        session.stepSlide(-5)
        XCTAssertEqual(session.currentSlide, 0)
        session.hide()
    }

    /// Regression: clicking to the next slide mid-sentence. The recognizer keeps
    /// repeating the sentence's earlier words, and the speaker often finishes
    /// it; neither may pull the text back to the previous slide.
    func testManualSlideMidSentenceStaysOnChosenSlide() throws {
        let session = makeSession(mode: .voice, spoken: [
            "Heute zeige ich euch unser neues Produkt und seine wichtigsten Funktionen",
            "Die Zahlen für das dritte Quartal sind deutlich gestiegen",
            "Vielen Dank fürs Zuhören"])
        let body = session.script.body as NSString
        session.maximumOffset = 1000
        session.receiveTranscript("Heute zeige ich euch unser", segment: 0, endTime: 1)
        XCTAssertEqual(session.activeWordRange?.location, body.range(of: "unser").location)
        session.stepSlide(1)
        let anchor = try XCTUnwrap(session.slideTimeline?.anchor(forPage: 1))
        session.resolveJump(240, for: anchor)
        for heard in ["Heute zeige ich euch unser neues Produkt",
                      "Heute zeige ich euch unser neues Produkt und seine wichtigsten Funktionen"] {
            session.receiveTranscript(heard, segment: 0, endTime: 2)
            XCTAssertNil(session.activeWordRange, "no jump back for: \(heard)")
            XCTAssertEqual(session.currentSlide, 1)
            session.advanceReading(by: 0.5)
            XCTAssertEqual(session.offset, 240)
        }
        session.receiveTranscript("Die Zahlen für das dritte", segment: 3, endTime: 4)
        XCTAssertEqual(session.activeWordRange?.location, body.range(of: "dritte").location)
        XCTAssertEqual(session.currentSlide, 1)
        session.hide()
    }

    /// Regression: after stepping on at a [Weiter] cue the text before it lit
    /// up again. It stays dimmed as if spoken; stepping back brightens it.
    func testManualStepKeepsEarlierTextDimmed() async throws {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.value.mode = .voice
        let session = PrompterSession(preferences: preferences)
        var presentation = deck(["A", "B", "C"], spoken: ["Erst der Markt heute. [Weiter] Dann unser Anteil.", "", "Vielen Dank."])
        presentation.groupWithNext(presentation.sections[0].id)
        var script = Script(title: "Talk", body: "")
        script.presentation = presentation
        script.body = PresentationComposer.compose(presentation).body
        session.script = script
        session.reset()
        session.gate = PlaybackGate(isVisible: true, isPlaying: true, isHovering: false, countdown: 0)
        let host = NSHostingView(rootView: ReaderView(session: session, preferences: preferences.value))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        func reader(in view: NSView) -> ReaderViewport? {
            if let reader = view as? ReaderViewport { return reader }
            return view.subviews.lazy.compactMap { reader(in: $0) }.first
        }
        let viewport = try XCTUnwrap(reader(in: host))
        let text = try XCTUnwrap((viewport.subviews.first as? NSClipView)?.documentView as? NSTextView)
        let manager = try XCTUnwrap(text.layoutManager)
        let body = script.body as NSString
        func dimmed(_ word: String) -> Bool {
            (manager.temporaryAttribute(.foregroundColor, atCharacterIndex: body.range(of: word).location, effectiveRange: nil) as? NSColor).map { abs(Double($0.alphaComponent) - ScriptStyle.spokenAlpha) < 0.001 } ?? false
        }
        session.receiveTranscript("Erst der", segment: 0, endTime: 1)
        session.stepSlide(1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(session.activeWordRange)
        XCTAssertTrue(dimmed("Markt"), "skipped text before [Weiter] counts as spoken")
        XCTAssertTrue(dimmed("heute"))
        XCTAssertFalse(dimmed("Dann"), "the chosen step is still to read")
        session.receiveTranscript("Dann unser", segment: 2, endTime: 3)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(dimmed("Dann"))
        XCTAssertTrue(dimmed("heute"))
        session.stepSlide(-1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(dimmed("Markt"), "stepping back brightens the text again")
        XCTAssertFalse(dimmed("Dann"))
        session.hide()
    }

    /// Regression: the speaking-pace estimate of the old slide used to scroll
    /// the text back after a manual slide change.
    func testManualSlideDropsSpeakingPaceOfPreviousPosition() throws {
        let session = makeSession(mode: .voice, spoken: [
            "Moderne Speicher liefern nachhaltige Energie für unsere gemeinsame Zukunft",
            "Die Zahlen für das dritte Quartal sind deutlich gestiegen",
            "Vielen Dank fürs Zuhören"])
        session.preferences.value.speechPacedScrolling = true
        session.maximumOffset = 10_000
        session.voiceGeometry = { $0 }
        let words = ["Moderne", "Speicher", "liefern", "nachhaltige", "Energie", "für"]
        var frame = 0
        func tick(_ count: Int) {
            for _ in 0..<count {
                frame += 1
                session.speech.level = frame % 3 == 0 ? 0.04 : 0.6
                session.advanceReading(by: 0.05)
            }
        }
        for count in 1...words.count {
            session.receiveTranscript(words.prefix(count).joined(separator: " "), segment: 0, endTime: Double(count) * 0.35)
            tick(7)
        }
        XCTAssertGreaterThan(session.offset, 0)
        session.stepSlide(1)
        let anchor = try XCTUnwrap(session.slideTimeline?.anchor(forPage: 1))
        session.resolveJump(Double(anchor), for: anchor)
        tick(40)
        XCTAssertEqual(session.offset, Double(anchor), "stays on the chosen slide")
        session.hide()
    }

    func testScrollingModesFollowFocusLineAndAdoptManualJump() {
        let session = makeSession(mode: .automatic)
        let body = session.script.body as NSString
        session.readerReached(character: body.range(of: "zusammen").location)
        XCTAssertEqual(session.currentSlide, 0)
        session.readerReached(character: body.range(of: "[Nächste Folie]").location)
        XCTAssertEqual(session.currentSlide, 1)
        session.stepSlide(1)
        XCTAssertEqual(session.currentSlide, 2)
        // The first position after a jump may lie just before the slide's cue.
        session.readerReached(character: body.range(of: "deutlich").location)
        XCTAssertEqual(session.currentSlide, 2)
        session.readerReached(character: body.range(of: "Vielen").location)
        XCTAssertEqual(session.currentSlide, 2)
        session.reset()
        XCTAssertEqual(session.currentSlide, 0)
        session.hide()
    }

    func testSlidesFollowReadingCanBeTurnedOffInEveryMode() {
        for mode in PlaybackMode.allCases {
            let session = makeSession(mode: mode)
            session.preferences.value.slidesFollowReading = false
            let body = session.script.body as NSString
            if mode == .voice {
                session.receiveTranscript("Hallo zusammen heute", segment: 0, endTime: 1)
            } else {
                session.readerReached(character: body.range(of: "[Nächste Folie]").location)
            }
            XCTAssertEqual(session.currentSlide, 0, "\(mode)")
            // Manual changes still move the slide and the text.
            session.maximumOffset = 1000
            session.stepSlide(1)
            XCTAssertEqual(session.currentSlide, 1)
            XCTAssertEqual(session.jumpCharacter, session.slideTimeline?.anchor(forPage: 1))
            session.preferences.value.slidesFollowReading = true
            if mode == .voice {
                session.receiveTranscript("Unsere Zahlen steigen deutlich", segment: 1, endTime: 2)
            } else {
                session.readerReached(character: body.range(of: "deutlich").location)
                session.readerReached(character: body.range(of: "Vielen").location)
            }
            XCTAssertEqual(session.currentSlide, 2, "turning it back on resumes at the next cue (\(mode))")
            session.hide()
        }
    }

    func testLegacyPreferencesKeepSlidesFollowingReading() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any])
        legacy["slidesFollow"] = nil
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "preferences.v1")
        let store = PreferenceStore(defaults: defaults)
        XCTAssertTrue(store.value.slidesFollowReading)
        store.value.slidesFollowReading = false
        XCTAssertFalse(PreferenceStore(defaults: defaults).value.slidesFollowReading)
    }

    func testTimerResetRestartsPrompterAndPresenterClocksOnly() throws {
        let session = makeSession(mode: .automatic)
        session.maximumOffset = 1000
        session.advanceReading(by: 0.1)
        for _ in 0..<20 { session.advanceReading(by: 0.1) }
        XCTAssertEqual(session.elapsedSeconds, 2)
        session.stepSlide(1)
        let offset = session.offset
        session.resetTimer()
        XCTAssertEqual(session.elapsedSeconds, 0)
        XCTAssertEqual(session.elapsed, 0)
        XCTAssertEqual(session.offset, offset, "position stays")
        XCTAssertEqual(session.currentSlide, 1, "slide stays")
        XCTAssertTrue(session.gate.isPlaying, "playback stays")
        session.advanceReading(by: 0.5)
        XCTAssertEqual(session.elapsed, 0.5, accuracy: 0.001)
        session.hide()

        let model = AppModel.shared
        let before = model.presenter.startedAt
        model.session.elapsed = 42
        model.resetTimers()
        XCTAssertEqual(model.session.elapsed, 0)
        XCTAssertGreaterThan(model.presenter.startedAt, before)
    }

    func testPlainScriptsHaveNoSlides() {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let session = PrompterSession(preferences: preferences)
        session.script = .welcome
        session.reset()
        XCTAssertNil(session.slideStatus)
        session.stepSlide(1)
        XCTAssertNil(session.jumpCharacter)
    }

    func testReaderResolvesSlideJump() async throws {
        let session = makeSession(mode: .automatic, spoken: Array(repeating: String(repeating: "Ein langer Satz für viele Zeilen. ", count: 12), count: 3))
        session.gate.isPlaying = false
        let view = ReaderViewport(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        view.update(preferences: session.preferences.value)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(session.maximumOffset, 400)
        session.stepSlide(2)
        view.update(preferences: session.preferences.value)
        XCTAssertNil(session.jumpCharacter)
        XCTAssertGreaterThan(session.offset, 400)
        let clip = try XCTUnwrap(view.subviews.first as? NSClipView)
        XCTAssertEqual(clip.bounds.minY, session.offset, accuracy: 1)
        XCTAssertEqual(session.currentSlide, 2)
        session.stepSlide(-1)
        view.update(preferences: session.preferences.value)
        XCTAssertEqual(session.currentSlide, 1)
        session.hide()
    }

    /// Regression: in voice mode scrolling past a slide cue did not change the slide.
    func testManualMovesChangeSlidesInEveryModeUnlessTurnedOff() async throws {
        for mode in PlaybackMode.allCases {
            for follows in [true, false] {
                let session = makeSession(mode: mode, spoken: Array(repeating: String(repeating: "Ein langer Satz für viele Zeilen. ", count: 12), count: 3))
                session.gate.isPlaying = false
                session.preferences.value.slidesFollowReading = follows
                let view = ReaderViewport(session: session)
                view.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
                view.update(preferences: session.preferences.value)
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
                XCTAssertEqual(session.currentSlide, 0)
                // Scroll wheel over the prompter: hover stays on.
                session.setHover(true)
                while session.currentSlide == 0, session.offset < session.maximumOffset {
                    session.scrollWheel(deltaY: -40, precise: true)
                }
                XCTAssertEqual(session.currentSlide, follows ? 1 : 0, "scroll wheel, \(mode)")
                session.setHover(false)
                // Keys and iPhone use nudge.
                let before = session.currentSlide
                while session.currentSlide == before, session.offset < session.maximumOffset { session.nudge(80) }
                XCTAssertEqual(session.currentSlide, follows ? 2 : 0, "keys, \(mode)")
                session.hide()
            }
        }
    }
}

@MainActor
final class PresentationFileTests: XCTestCase {
    /// Builds a real PDF with CoreText so PDFKit extracts the page text.
    static func makePDF(_ pages: [String], at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for (index, text) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: index.isMultiple(of: 2) ? 0.9 : 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320 + index * 40, height: 360))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 28)]))
            context.textPosition = CGPoint(x: 40, y: 180)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    func testImportReadsTextAndUpdatedVersionKeepsAssignments() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "Vortrag.pdf")
        try Self.makePDF(["Willkommen zum Vortrag", "Unsere Ergebnisse", "Danke"], at: original)
        let files = PresentationFiles(folder: folder.appending(path: "Presentations"))
        var deck = try await files.makeDeck(from: original, text: "Hallo")
        XCTAssertEqual(deck.pages.count, 3)
        XCTAssertEqual(deck.pages[1].text, "unsere ergebnisse")
        XCTAssertNotEqual(deck.pages[0].imageHash, deck.pages[1].imageHash)
        XCTAssertEqual(deck.sections[0].text, "Hallo")
        XCTAssertNotNil(files.document(for: deck))
        XCTAssertNotNil(files.thumbnail(deck, page: 0, width: 120))
        deck.setText("Ergebnistext", section: deck.sections[1].id)

        try Self.makePDF(["Willkommen zum Vortrag", "Agenda für heute", "Unsere Ergebnisse", "Danke"], at: original)
        let snapshot = try await PresentationFiles.read(original)
        let change = try files.apply(snapshot, from: original, to: &deck)
        XCTAssertEqual(change.added, 1)
        XCTAssertEqual(deck.sections.map(\.text), ["Hallo", "", "Ergebnistext", ""])
        XCTAssertEqual(files.document(for: deck)?.pageCount, 4)

        let copy = try XCTUnwrap(files.duplicate(deck))
        XCTAssertNotEqual(copy.id, deck.id)
        XCTAssertEqual(files.document(for: copy)?.pageCount, 4)
        files.remove(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.storedURL(for: copy).path))
    }

    func testUnreadableFileIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try Data("kein pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await PresentationFiles.read(url)
            XCTFail("expected an error")
        } catch let error as PresentationError {
            XCTAssertEqual(error.errorDescription, PresentationError.unreadable.errorDescription)
        }
    }
}

@MainActor
final class PresentationRenderTests: XCTestCase {
    /// Renders the slide editor, presenter view and audience view from the
    /// real SwiftUI views with a generated PDF.
    func testPresentationViewsRender() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "Quartalsbericht.pdf")
        try PresentationFileTests.makePDF(["Quartalsbericht", "Umsatz", "Aufbau 1", "Aufbau 2", "Danke"], at: pdf)
        let model = AppModel.shared
        let files = model.presentationFiles
        model.presentationFiles = PresentationFiles(folder: folder.appending(path: "Presentations"))
        defer { model.presentationFiles = files; model.presenter.document = nil; model.session.script = .welcome; model.session.reset() }
        var deck = try await model.presentationFiles.makeDeck(from: pdf, text: "Willkommen zum Quartalsbericht. [Lächeln] Heute geht es um drei Zahlen.")
        deck.setText("Der Umsatz ist um zwölf Prozent gewachsen.", section: deck.sections[1].id)
        deck.groupWithNext(deck.sections[2].id)
        deck.setText("Erst der Markt. [Weiter] Dann unser Anteil.", section: deck.sections[2].id)
        deck.pages[4].flag = .added
        var script = Script(title: "Quartalsbericht", body: "")
        script.presentation = deck
        script.body = PresentationComposer.compose(deck).body

        model.session.script = script
        model.session.reset()
        model.session.stepSlide(1)
        // No windows: the views read the document directly.
        model.presenter.document = try XCTUnwrap(model.presentationFiles.document(for: deck))

        try snapshot(SlideEditorView(model: model, script: script, deck: deck).frame(width: 760, height: 760).background(Design.canvas), name: "slide-editor", size: CGSize(width: 760, height: 760))
        try snapshot(PresenterView(model: model, topReserve: 0), name: "presenter", size: CGSize(width: 1200, height: 700))
        try snapshot(AudienceView(model: model), name: "audience", size: CGSize(width: 960, height: 600))
    }

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1000)
        let url = FileManager.default.temporaryDirectory.appending(path: "macprompter-\(name).png")
        try data.write(to: url)
        print("PRESENTATION_SNAPSHOT: \(url.path)")
    }
}
