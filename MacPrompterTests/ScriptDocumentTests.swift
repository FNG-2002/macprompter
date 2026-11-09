import XCTest
@testable import MacPrompter

final class ScriptSettingsTests: XCTestCase {
    func testPreferencesRoundTripAndGlobalsStayUntouched() {
        var prefs = Preferences()
        prefs.displayID = 42; prefs.mirror = true; prefs.countdownSeconds = 5
        var settings = ScriptSettings()
        settings.mode = .voice; settings.speed = 80; settings.font = .openDyslexic; settings.fontSize = 40
        settings.lineSpacing = 20; settings.focusLine = false; settings.prompterOpacity = 0.5
        settings.docked = false; settings.width = 900; settings.height = 500; settings.presenterView = false
        prefs.scriptSettings = settings
        XCTAssertEqual(prefs.scriptSettings, settings)
        XCTAssertEqual(prefs.displayID, 42, "screen choice is per Mac, not per script")
        XCTAssertTrue(prefs.mirror)
        XCTAssertEqual(prefs.countdownSeconds, 5)
    }

    func testDecodingIsTolerantAndValuesAreClamped() throws {
        let json = #"{"mode":"telepathy","speed":9999,"fontSize":2,"width":100000,"prompterOpacity":-3,"unknown":true}"#
        let settings = try JSONDecoder().decode(ScriptSettings.self, from: Data(json.utf8)).clamped
        XCTAssertEqual(settings.mode, .automatic, "unknown values fall back")
        XCTAssertEqual(settings.speed, 120)
        XCTAssertEqual(settings.fontSize, 18)
        XCTAssertEqual(settings.width, Preferences.widthRange.upperBound)
        XCTAssertEqual(settings.prompterOpacity, 0.2)
        XCTAssertEqual(settings.height, 300, "missing keys use defaults")
    }

    @MainActor func testLibraryRemembersSettingsWithoutTouchingModificationDate() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ScriptLibrary(directory: folder)
        let id = library.add(title: "A", body: "Text")
        let modified = try XCTUnwrap(library.selected?.modifiedAt)
        var settings = ScriptSettings(); settings.speed = 70
        library.setSettings(settings, for: id)
        XCTAssertEqual(library.selected?.settings, settings)
        XCTAssertEqual(library.selected?.modifiedAt, modified)
        library.save()
        XCTAssertEqual(ScriptLibrary(directory: folder).scripts.first?.settings, settings)
    }
}

final class ScriptDocumentTests: XCTestCase {
    private func presentationScript() -> Script {
        var deck = PresentationDeck(fileName: "Talk.pdf", pages: [SlidePage(text: "a", imageHash: 1), SlidePage(text: "b", imageHash: 2)])
        deck.sections[0].text = "Hallo"
        deck.bookmark = Data("secret-path".utf8)
        var script = Script(title: "Talk: Q3/Q4", body: PresentationComposer.compose(deck).body, language: .english)
        script.presentation = deck
        return script
    }

    func testRoundTripKeepsEverythingButTheSendersBookmark() throws {
        var settings = ScriptSettings(); settings.mode = .voice; settings.prompterOpacity = 0.6
        let pdf = Data("%PDF-fake".utf8)
        let data = try ScriptDocument(script: presentationScript(), settings: settings, pdf: pdf).encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(Data("secret-path".utf8).base64EncodedString()))
        let decoded = try ScriptDocument.decode(data)
        XCTAssertEqual(decoded.script.title, "Talk: Q3/Q4")
        XCTAssertEqual(decoded.script.language, .english)
        XCTAssertEqual(decoded.script.settings, settings)
        XCTAssertEqual(decoded.script.presentation?.sections.first?.text, "Hallo")
        XCTAssertNil(decoded.script.presentation?.bookmark)
        XCTAssertEqual(decoded.pdf, pdf)
        XCTAssertEqual(decoded.version, ScriptDocument.currentVersion)
    }

    func testPlainScriptsCarryNoPDFAndRejectsForeignOrNewerFiles() throws {
        let plain = try ScriptDocument.decode(try ScriptDocument(script: .welcome, settings: ScriptSettings(), pdf: Data([1])).encoded())
        XCTAssertNil(plain.pdf)
        XCTAssertThrowsError(try ScriptDocument.decode(Data("Hallo".utf8))) { XCTAssertEqual($0 as? ScriptDocumentError, .notAScript) }
        XCTAssertThrowsError(try ScriptDocument.decode(Data(#"{"format":"other"}"#.utf8))) { XCTAssertEqual($0 as? ScriptDocumentError, .notAScript) }
        XCTAssertThrowsError(try ScriptDocument.decode(Data(#"{"format":"macprompter.script","version":7}"#.utf8))) {
            XCTAssertEqual($0 as? ScriptDocumentError, .newerVersion(7))
        }
        var withoutPDF = try JSONDecoder.iso.decode(JSONValue.self, from: try ScriptDocument(script: presentationScript(), settings: ScriptSettings(), pdf: Data([1])).encoded())
        if case .object(var object) = withoutPDF { object["pdf"] = nil; withoutPDF = .object(object) }
        XCTAssertThrowsError(try ScriptDocument.decode(withoutPDF.data)) { XCTAssertEqual($0 as? ScriptDocumentError, .missingPDF) }
    }

    func testFileNamesAreSafe() {
        XCTAssertEqual(ScriptDocument.fileName(for: "Talk: Q3/Q4"), "Talk- Q3-Q4.macprompter")
        XCTAssertEqual(ScriptDocument.fileName(for: "  "), "Skript.macprompter")
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

@MainActor
final class ScriptFileImportTests: XCTestCase {
    private var folder: URL!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    func testPresentationSurvivesExportAndImportWithNewIdentity() async throws {
        let files = PresentationFiles(folder: folder.appending(path: "Presentations"))
        let pdf = folder.appending(path: "Talk.pdf")
        try PresentationFileTests.makePDF(["Titel", "Schritt 1", "Schritt 2", "Danke"], at: pdf)
        var deck = try await files.makeDeck(from: pdf)
        XCTAssertTrue(deck.apply([TemplateSlide(pages: 1, text: "Hallo"), TemplateSlide(pages: 2, text: "Eins [Weiter] Zwei"), TemplateSlide(pages: 1, text: "Danke")]))
        var script = Script(title: "Talk", body: PresentationComposer.compose(deck).body)
        script.presentation = deck
        var settings = ScriptSettings(); settings.mode = .voice; settings.width = 1200

        let data = try ScriptFileExport(script: script, settings: settings, pdfURL: files.storedURL(for: deck)).encoded()
        let imported = try await AppModel.prepareImport(data, files: files)
        let importedDeck = try XCTUnwrap(imported.presentation)
        XCTAssertNotEqual(importedDeck.id, deck.id, "a new library copy, never the sender's")
        XCTAssertNil(importedDeck.bookmark)
        XCTAssertEqual(importedDeck.sections.map(\.text), ["Hallo", "Eins [Weiter] Zwei", "Danke"])
        XCTAssertEqual(importedDeck.pageIndices(of: importedDeck.sections[1]), [1, 2])
        XCTAssertEqual(imported.settings, settings)
        XCTAssertEqual(imported.body, script.body)
        XCTAssertEqual(files.document(for: importedDeck)?.pageCount, 4)

        let library = ScriptLibrary(directory: folder)
        let first = library.insert(imported)
        let second = library.insert(imported)
        XCTAssertNotEqual(first, second, "importing twice keeps both copies")
    }

    func testMCPExportAndImportRoundTrip() async throws {
        let library = ScriptLibrary(directory: folder)
        let files = PresentationFiles(folder: folder.appending(path: "Presentations"))
        let server = MCPServer(directory: folder)
        let tools = AgentTools(library: library, files: files)
        var settings = ScriptSettings(); settings.speed = 55
        tools.exportDocument = { script in try ScriptFileExport(script: script, settings: script.settings ?? settings, pdfURL: script.presentation.map(files.storedURL)).encoded() }
        tools.importDocument = { data in library.insert(try await AppModel.prepareImport(data, files: files), select: false) }
        server.tools = tools
        let id = library.add(title: "Pitch", body: "Hallo [Pause] Welt")
        library.setSettings(settings, for: id)

        func call(_ name: String, _ arguments: JSONValue) async throws -> JSONValue {
            let reply = await server.handle(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments]])
            let result = try XCTUnwrap(reply?["result"])
            XCTAssertEqual(result["isError"], false, result.text)
            return result["structuredContent"] ?? .null
        }
        let exported = try await call("export_script", ["script_id": .string(id.uuidString)])
        XCTAssertEqual(exported["file_name"], "Pitch.macprompter")
        let base64 = try XCTUnwrap(exported["file_base64"]?.string)
        let imported = try await call("import_script", ["file_base64": .string(base64)])
        XCTAssertEqual(library.scripts.count, 2)
        XCTAssertNotEqual(imported["script_id"]?.string, id.uuidString)
        XCTAssertEqual(imported["text"], "Hallo [Pause] Welt")
        XCTAssertEqual(library.scripts.first { $0.id.uuidString == imported["script_id"]?.string }?.settings?.speed, 55)

        let broken = await server.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "import_script", "arguments": ["file_base64": .string(Data("nope".utf8).base64EncodedString())]]])
        XCTAssertEqual(broken?["result"]?["isError"], true)
        let noFolder = await server.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "export_script", "arguments": ["script_id": .string(id.uuidString), "path": "x"]]])
        XCTAssertEqual(noFolder?["result"]?["isError"], true)
    }
}
