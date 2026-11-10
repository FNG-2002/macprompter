import Foundation

/// Editor functions exposed to AI agents over MCP. Every change goes through
/// `ScriptLibrary`, exactly like the UI, so edits appear in the open editor.
/// Agents can create and edit but never delete scripts.
@MainActor
final class AgentTools {
    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

    let library: ScriptLibrary
    let files: PresentationFiles
    /// Folder the user shared for PDFs; the sandbox cannot read arbitrary paths.
    var pdfFolder: () -> URL? = { nil }
    /// Lets the app refresh a visible prompter after a change.
    var didChange: (UUID) -> Void = { _ in }
    var select: (UUID) -> Void = { _ in }
    /// `.macprompter` files, provided by the app (they include the side-pane settings).
    var exportDocument: (Script) throws -> Data = { _ in throw Failure("Export nicht verfügbar.") }
    var importDocument: (Data) async throws -> UUID = { _ in throw Failure("Import nicht verfügbar.") }

    init(library: ScriptLibrary, files: PresentationFiles) {
        self.library = library
        self.files = files
    }

    // MARK: Definitions

    static let definitions: [JSONValue] = [
        tool("list_scripts", "Skripte auflisten",
             "Lists all scripts in the macprompter library with id, title, language, word count and, for presentations, the number of slides.",
             #"{"type":"object","properties":{}}"#, readOnly: true),
        tool("get_script", "Skript lesen",
             "Returns a script. Plain scripts return their text. Presentations return one entry per slide with the spoken text (speaker notes) and the PDF pages that belong to it; a slide spanning several pages is revealed in steps. Text in [brackets] is a stage direction that is shown but not spoken; [Weiter] inside a slide text advances to its next step.",
             #"{"type":"object","properties":{"script_id":{"type":"string","description":"Script id from list_scripts"}},"required":["script_id"]}"#, readOnly: true),
        tool("create_script", "Skript anlegen",
             "Creates a new plain teleprompter script. Use blank lines between paragraphs and [stage directions] in brackets, e.g. [Pause] or [Lächeln].",
             #"{"type":"object","properties":{"title":{"type":"string"},"text":{"type":"string"},"language":{"type":"string","description":"Speech recognition language as code or locale, e.g. de, en, fr, tr, de-CH; default de"}},"required":["title","text"]}"#),
        tool("update_script", "Skript ändern",
             "Changes title, language or text of a script. For presentations only title and language can be changed here; use set_slide_text or set_slides for the slide texts.",
             #"{"type":"object","properties":{"script_id":{"type":"string"},"title":{"type":"string"},"text":{"type":"string"},"language":{"type":"string","description":"Speech recognition language as code or locale, e.g. de, en, fr, tr, de-CH"}},"required":["script_id"]}"#),
        tool("create_presentation", "Präsentation anlegen",
             "Creates a presentation from a PDF and optionally sets the spoken text per slide. Pass pdf_path (a file inside the folder the user shared in macprompter's settings, absolute or relative to it) or pdf_base64 for small files. slides is an ordered list; give steps > 1 when a slide spans several consecutive PDF pages (builds). Without steps every PDF page is one slide.",
             #"{"type":"object","properties":{"title":{"type":"string"},"pdf_path":{"type":"string"},"pdf_base64":{"type":"string"},"language":{"type":"string","description":"Speech recognition language as code or locale, e.g. de, en, fr, tr, de-CH"},"slides":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"steps":{"type":"integer","minimum":1}},"required":["text"]}}},"required":["title"]}"#),
        tool("set_slide_text", "Folientext setzen",
             "Sets the spoken text (speaker notes) of one slide. Slides are numbered from 1 as returned by get_script; slides without a PDF page are addressed by section_id.",
             #"{"type":"object","properties":{"script_id":{"type":"string"},"slide":{"type":"integer","minimum":1},"section_id":{"type":"string"},"text":{"type":"string"}},"required":["script_id","text"]}"#),
        tool("set_slides", "Alle Folientexte setzen",
             "Replaces the texts of all slides in order. If any entry has steps, the steps must add up to the number of PDF pages and also regroup the pages into slides.",
             #"{"type":"object","properties":{"script_id":{"type":"string"},"slides":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"steps":{"type":"integer","minimum":1}},"required":["text"]}}},"required":["script_id","slides"]}"#),
        tool("replace_presentation_pdf", "Neue PDF-Version",
             "Replaces the PDF of a presentation with a new version. Texts stay with their slides even when pages were inserted, removed, moved or edited; new pages get empty slides.",
             #"{"type":"object","properties":{"script_id":{"type":"string"},"pdf_path":{"type":"string"},"pdf_base64":{"type":"string"}},"required":["script_id"]}"#),
        tool("export_script", "Als macprompter-Datei sichern",
             "Saves a script as a self-contained .macprompter file: text, slides with the embedded PDF and the script's side-pane settings (mode, speed, font, size, position, opacity). Pass path (inside the folder shared in macprompter's settings, absolute or relative) to write the file; without path the file is returned as file_base64.",
             #"{"type":"object","properties":{"script_id":{"type":"string"},"path":{"type":"string","description":"Target file inside the shared folder; .macprompter is appended if missing"}},"required":["script_id"]}"#, readOnly: true),
        tool("import_script", "macprompter-Datei laden",
             "Imports a .macprompter file as a new script (never replaces an existing one). Pass path inside the shared folder or file_base64.",
             #"{"type":"object","properties":{"path":{"type":"string"},"file_base64":{"type":"string"}}}"#),
        tool("select_script", "Skript öffnen",
             "Shows a script in macprompter's editor.",
             #"{"type":"object","properties":{"script_id":{"type":"string"}},"required":["script_id"]}"#),
    ]

    private static func tool(_ name: String, _ title: String, _ description: String, _ schema: String, readOnly: Bool = false) -> JSONValue {
        ["name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": JSONValue.parse(schema),
         "annotations": ["readOnlyHint": .bool(readOnly), "destructiveHint": false, "openWorldHint": false]]
    }

    // MARK: Calls

    func call(_ name: String, _ arguments: JSONValue) async throws -> JSONValue {
        switch name {
        case "list_scripts": return ["scripts": .array(library.scripts.map(summary))]
        case "get_script": return try detail(script(arguments))
        case "create_script":
            let title = try required(arguments, "title")
            let id = library.add(title: title, body: try required(arguments, "text", allowEmpty: true), language: try language(arguments) ?? .german, select: false)
            return ["script_id": .string(id.uuidString), "title": .string(title)]
        case "update_script": return try updateScript(arguments)
        case "create_presentation": return try await createPresentation(arguments)
        case "set_slide_text": return try setSlideText(arguments)
        case "set_slides":
            let script = try script(arguments)
            var deck = try presentation(script)
            try apply(slides: arguments["slides"]?.array ?? [], to: &deck)
            store(deck, script.id)
            return try detail(library.scripts.first { $0.id == script.id }!)
        case "replace_presentation_pdf": return try await replacePDF(arguments)
        case "export_script": return try exportScript(arguments)
        case "import_script":
            let data: Data
            if let base64 = arguments["file_base64"]?.string {
                guard let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { throw Failure("file_base64 ist kein gültiges Base64.") }
                data = decoded
            } else {
                guard let path = arguments["path"]?.string, !path.isEmpty else { throw Failure("Gib path oder file_base64 an.") }
                let (url, stop) = try sharedFile(path, mustExist: true)
                defer { stop() }
                data = try Data(contentsOf: url)
            }
            let id: UUID
            do { id = try await importDocument(data) } catch let error as ScriptDocumentError { throw Failure(error.errorDescription ?? "Ungültige Datei.") }
            return try detail(library.scripts.first { $0.id == id }!)
        case "select_script":
            let script = try script(arguments)
            select(script.id)
            return ["script_id": .string(script.id.uuidString), "title": .string(script.title)]
        default: throw Failure("Unbekanntes Werkzeug: \(name)")
        }
    }

    private func updateScript(_ arguments: JSONValue) throws -> JSONValue {
        let script = try script(arguments)
        let text = arguments["text"]?.string
        if text != nil && script.presentation != nil {
            throw Failure("Dieses Skript ist eine Präsentation. Ändere die Texte mit set_slide_text oder set_slides.")
        }
        let title = arguments["title"]?.string
        if let title, title.trimmingCharacters(in: .whitespaces).isEmpty { throw Failure("Der Titel darf nicht leer sein.") }
        library.update(id: script.id, title: title, body: text, language: try language(arguments))
        didChange(script.id)
        return try detail(library.scripts.first { $0.id == script.id }!)
    }

    private func createPresentation(_ arguments: JSONValue) async throws -> JSONValue {
        let title = try required(arguments, "title")
        let (url, access) = try pdf(arguments)
        defer { access() }
        var deck = try await files.makeDeck(from: url)
        if arguments["pdf_base64"] != nil { deck.bookmark = nil; deck.fileName = "\(title).pdf" }
        if let slides = arguments["slides"]?.array, !slides.isEmpty {
            do { try apply(slides: slides, to: &deck) } catch { files.remove(deck); throw error }
        }
        let id = library.add(title: title, language: try language(arguments) ?? .german, presentation: deck, select: false)
        return try detail(library.scripts.first { $0.id == id }!)
    }

    private func replacePDF(_ arguments: JSONValue) async throws -> JSONValue {
        let script = try script(arguments)
        _ = try presentation(script)
        let (url, access) = try pdf(arguments)
        defer { access() }
        let snapshot = try await PresentationFiles.read(url)
        // Apply to the latest deck; texts may have changed while the PDF was read.
        guard var deck = library.scripts.first(where: { $0.id == script.id })?.presentation else { throw Failure("Die Präsentation gibt es nicht mehr.") }
        let change = try files.apply(snapshot, from: url, to: &deck)
        if arguments["pdf_base64"] != nil { deck.bookmark = nil; deck.fileName = script.presentation?.fileName ?? deck.fileName }
        store(deck, script.id)
        var result = try detail(library.scripts.first { $0.id == script.id }!)
        if case .object(var object) = result {
            object["change"] = ["added": .number(Double(change.added)), "removed": .number(Double(change.removed)),
                                "changed": .number(Double(change.changed)), "summary": .string(change.summary)]
            result = .object(object)
        }
        return result
    }

    private func setSlideText(_ arguments: JSONValue) throws -> JSONValue {
        let script = try script(arguments)
        var deck = try presentation(script)
        let text = try required(arguments, "text", allowEmpty: true)
        let section: SlideSection?
        if let id = arguments["section_id"]?.string {
            section = deck.sections.first { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }
        } else if let slide = arguments["slide"]?.int {
            let numbered = deck.sections.filter { !$0.pageIDs.isEmpty }
            section = numbered.indices.contains(slide - 1) ? numbered[slide - 1] : nil
        } else { throw Failure("Gib slide (ab 1) oder section_id an.") }
        guard let section else { throw Failure("Diese Folie gibt es nicht. get_script zeigt alle Folien.") }
        deck.setText(text, section: section.id)
        store(deck, script.id)
        return try detail(library.scripts.first { $0.id == script.id }!)
    }

    /// With steps: regroups all pages. Without: sets texts of the numbered slides in order.
    private func apply(slides: [JSONValue], to deck: inout PresentationDeck) throws {
        let entries = try slides.map { entry -> (text: String, steps: Int?) in
            guard let text = entry["text"]?.string else { throw Failure("Jede Folie braucht ein Feld text.") }
            let steps = entry["steps"]?.int
            if let steps, steps < 1 { throw Failure("steps muss mindestens 1 sein.") }
            return (text, steps)
        }
        if entries.contains(where: { $0.steps != nil }) {
            let templates = entries.map { TemplateSlide(pages: $0.steps ?? 1, text: $0.text) }
            let total = templates.reduce(0) { $0 + $1.pages }
            guard deck.apply(templates) else { throw Failure("Die Schritte ergeben \(total) Seiten, die PDF hat \(deck.pages.count).") }
            return
        }
        let numbered = deck.sections.filter { !$0.pageIDs.isEmpty }
        guard entries.count <= numbered.count else {
            throw Failure("\(entries.count) Texte, aber nur \(numbered.count) Folien. Mit steps lassen sich PDF-Seiten zu einer Folie zusammenfassen.")
        }
        for (entry, section) in zip(entries, numbered) { deck.setText(entry.text, section: section.id) }
    }

    // MARK: Helpers

    private func store(_ deck: PresentationDeck, _ id: UUID) {
        library.updatePresentation(deck, for: id)
        didChange(id)
    }

    private func script(_ arguments: JSONValue) throws -> Script {
        let id = try required(arguments, "script_id")
        guard let script = library.scripts.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
            throw Failure("Kein Skript mit der id \(id). list_scripts zeigt alle Skripte.")
        }
        return script
    }

    private func presentation(_ script: Script) throws -> PresentationDeck {
        guard let deck = script.presentation else { throw Failure("„\(script.title)“ ist keine Präsentation.") }
        return deck
    }

    private func required(_ arguments: JSONValue, _ key: String, allowEmpty: Bool = false) throws -> String {
        guard let value = arguments[key]?.string, allowEmpty || !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Failure("Pflichtfeld fehlt: \(key)")
        }
        return value
    }

    private func language(_ arguments: JSONValue) throws -> SpeechLanguage? {
        guard let value = arguments["language"]?.string else { return nil }
        guard let language = SpeechLanguage(code: value) else { throw Failure("language muss ein Sprachcode sein, z. B. de, en, fr oder tr.") }
        return language
    }

    private func exportScript(_ arguments: JSONValue) throws -> JSONValue {
        let script = try script(arguments)
        let data = try exportDocument(script)
        let name = ScriptDocument.fileName(for: script.title)
        guard var path = arguments["path"]?.string, !path.isEmpty else {
            return ["file_name": .string(name), "bytes": .number(Double(data.count)), "file_base64": .string(data.base64EncodedString())]
        }
        if !path.lowercased().hasSuffix("." + ScriptDocument.fileExtension) { path += "." + ScriptDocument.fileExtension }
        let (url, stop) = try sharedFile(path, mustExist: false)
        defer { stop() }
        try data.write(to: url, options: .atomic)
        return ["path": .string(url.path), "bytes": .number(Double(data.count))]
    }

    /// Resolves the PDF argument to a readable file and returns a closure that ends access.
    private func pdf(_ arguments: JSONValue) throws -> (URL, () -> Void) {
        if let base64 = arguments["pdf_base64"]?.string {
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { throw Failure("pdf_base64 ist kein gültiges Base64.") }
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
            try data.write(to: url)
            return (url, { try? FileManager.default.removeItem(at: url) })
        }
        guard let path = arguments["pdf_path"]?.string, !path.isEmpty else { throw Failure("Gib pdf_path oder pdf_base64 an.") }
        return try sharedFile(path, mustExist: true)
    }

    /// A file inside the shared folder; `../` and symlinks out of it are rejected.
    private func sharedFile(_ path: String, mustExist: Bool) throws -> (URL, () -> Void) {
        guard let folder = pdfFolder() else {
            throw Failure("Kein Ordner freigegeben. Bitte in macprompter unter Einstellungen → KI-Agenten einen Ordner wählen oder die Datei als Base64 übergeben.")
        }
        let access = folder.startAccessingSecurityScopedResource()
        let stop = { if access { folder.stopAccessingSecurityScopedResource() } }
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appending(path: path)).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else {
            stop()
            throw Failure("Die Datei muss im freigegebenen Ordner liegen: \(base.path)")
        }
        guard mustExist else {
            // New files: the parent must exist inside the folder.
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else {
                stop()
                throw Failure("Ordner nicht gefunden: \(url.deletingLastPathComponent().path)")
            }
            return (url, stop)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            stop()
            throw Failure("Datei nicht gefunden oder nicht lesbar: \(url.path)")
        }
        return (url, stop)
    }

    private func summary(_ script: Script) -> JSONValue {
        var object: [String: JSONValue] = ["script_id": .string(script.id.uuidString), "title": .string(script.title),
            "language": .string(script.language.shortCode),
            "words": .number(Double(ScriptParser.words(in: script.body).count)),
            "modified_at": .string(ISO8601DateFormatter().string(from: script.modifiedAt))]
        if let deck = script.presentation {
            object["slides"] = .number(Double(deck.sections.filter { !$0.pageIDs.isEmpty }.count))
            object["pdf_pages"] = .number(Double(deck.pages.count))
        }
        return .object(object)
    }

    private func detail(_ script: Script) throws -> JSONValue {
        guard case .object(var object) = summary(script) else { return .null }
        guard let deck = script.presentation else {
            object["text"] = .string(script.body)
            return .object(object)
        }
        object["pdf"] = .string(deck.fileName)
        var number = 0
        object["slides"] = .array(deck.sections.map { section in
            let pages = deck.pageIndices(of: section)
            var entry: [String: JSONValue] = ["section_id": .string(section.id.uuidString), "text": .string(section.text),
                "pdf_pages": .array(pages.map { .number(Double($0 + 1)) }), "steps": .number(Double(max(1, pages.count)))]
            if pages.isEmpty { entry["slide"] = .null; entry["note"] = "PDF-Seite wurde entfernt; Text bleibt erhalten." }
            else { number += 1; entry["slide"] = .number(Double(number)) }
            if let flag = pages.compactMap({ deck.pages[$0].flag }).first { entry["flag"] = .string(flag.rawValue) }
            return .object(entry)
        })
        return .object(object)
    }
}
