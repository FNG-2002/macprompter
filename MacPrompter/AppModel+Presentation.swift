import AppKit
import UniformTypeIdentifiers

/// PDF presentations: linking, updating, editing sections and presenting.
extension AppModel {
    var slideStatus: SlideStatus? { session.slideStatus }
    var isPresenting: Bool { presenter.isPresenting }

    func stepSlide(_ delta: Int) { session.stepSlide(delta) }
    func showSlide(_ page: Int) { session.showSlide(page) }

    func startPresentation() {
        guard let script = library.selected, script.presentation != nil else { return }
        Task {
            await refreshPresentation()
            guard library.selectedID == script.id, let deck = library.selected?.presentation else { return }
            guard let document = presentationFiles.document(for: deck) else {
                library.errorMessage = "Die PDF dieser Präsentation fehlt. Wähle sie über „PDF ersetzen …“ erneut aus."
                return
            }
            preview()
            presenter.start(document: document)
        }
    }

    func endPresentation() { presenter.end() }

    func importPresentation() {
        pickPDF(title: "PDF-Präsentation importieren") { [weak self] url in
            guard let self else { return }
            let deck = try await self.presentationFiles.makeDeck(from: url)
            self.library.add(title: url.deletingPathExtension().lastPathComponent, presentation: deck)
        }
    }

    /// Links a PDF to the selected plain script; its text moves to the first slide.
    func attachPresentation() {
        guard let script = library.selected, script.presentation == nil else { return }
        pickPDF(title: "PDF mit „\(script.title)“ verknüpfen") { [weak self] url in
            guard let self, let current = self.library.scripts.first(where: { $0.id == script.id }) else { return }
            let deck = try await self.presentationFiles.makeDeck(from: url, text: current.body)
            self.applyPresentation(deck, to: script.id)
        }
    }

    func replacePresentationPDF() {
        guard let script = library.selected, script.presentation != nil else { return }
        pickPDF(title: "Neue Version der PDF wählen") { [weak self] url in
            guard let self else { return }
            let snapshot = try await PresentationFiles.read(url)
            try self.adopt(snapshot, from: url, scriptID: script.id, announce: true)
        }
    }

    /// Converts the presentation back into a plain script without slide cues.
    func detachPresentation() {
        guard let script = library.selected, let deck = script.presentation else { return }
        if presenter.isPresenting { presenter.end() }
        presentationFiles.remove(deck)
        applyPresentation(nil, to: script.id)
    }

    /// Picks up a re-exported PDF. Runs when the editor appears, when the app
    /// becomes active and before presenting; never during a presentation.
    func refreshPresentation(force: Bool = false) async {
        guard !presenter.isPresenting, !isUpdatingPresentation,
              let script = library.selected, let deck = script.presentation else { return }
        isUpdatingPresentation = true
        defer { isUpdatingPresentation = false }
        do {
            guard let (snapshot, url) = try await presentationFiles.changedSnapshot(of: deck, force: force) else {
                if force { library.errorMessage = "Die Originaldatei „\(deck.fileName)“ ist nicht erreichbar. Wähle sie über „PDF ersetzen …“ neu aus." }
                return
            }
            try adopt(snapshot, from: url, scriptID: script.id, announce: true)
        } catch {
            library.errorMessage = "Die PDF konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func editPresentation(_ transform: (inout PresentationDeck) -> Void) {
        guard let script = library.selected, var deck = script.presentation else { return }
        transform(&deck)
        applyPresentation(deck, to: script.id)
    }

    func dismissPresentationChange() {
        presentationChange = nil
        editPresentation { $0.clearFlags() }
    }

    func duplicateSelectedScript() {
        let copy = library.selected?.presentation.flatMap(presentationFiles.duplicate)
        if library.selected?.presentation != nil && copy == nil {
            library.errorMessage = "Die PDF konnte nicht kopiert werden."
            return
        }
        library.duplicate(presentation: copy)
    }

    func deleteSelectedScript() {
        if session.script.id == library.selectedID { presenter.end(); session.hide() }
        if let deck = library.selected?.presentation { presentationFiles.remove(deck) }
        library.deleteSelected()
    }

    func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                AppModel.shared.refreshScrollAccess()
                await AppModel.shared.refreshPresentation()
            }
        }
    }

    private func adopt(_ snapshot: PresentationFiles.Snapshot, from url: URL, scriptID: UUID, announce: Bool) throws {
        // Apply to the latest deck so text typed during parsing is kept.
        guard var deck = library.scripts.first(where: { $0.id == scriptID })?.presentation else { return }
        let change = try presentationFiles.apply(snapshot, from: url, to: &deck)
        applyPresentation(deck, to: scriptID)
        if announce { presentationChange = (scriptID, change) }
    }

    private func applyPresentation(_ deck: PresentationDeck?, to id: UUID) {
        library.updatePresentation(deck, for: id)
        if session.gate.isVisible, session.script.id == id, let script = library.scripts.first(where: { $0.id == id }) {
            session.pause(); session.present(script)
        }
    }

    private func pickPDF(title: String, _ handle: @escaping @MainActor (URL) async throws -> Void) {
        let panel = NSOpenPanel()
        panel.message = title
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await handle(url) }
                catch { self?.library.errorMessage = "PDF-Import fehlgeschlagen: \(error.localizedDescription)" }
            }
        }
    }

    /// Copies a template into the library as a new, independent script.
    func createScript(from template: ScriptTemplate, title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.title : title
        guard let resource = template.pdfResource else {
            library.add(title: name, body: template.body, language: template.language)
            return
        }
        do {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "pdf") else { throw PresentationError.unreadable }
            var deck = try await presentationFiles.makeDeck(from: url)
            // The bundled PDF is not a document the user edits; no original to watch.
            deck.bookmark = nil
            deck.fileName = "\(name).pdf"
            guard deck.apply(template.slides) else { throw PresentationError.unreadable }
            library.add(title: name, language: template.language, presentation: deck)
        } catch {
            library.errorMessage = "Die Vorlage konnte nicht angelegt werden: \(error.localizedDescription)"
        }
    }

    /// Wires the MCP endpoint to the library; agents edit through the same paths as the UI.
    func setupAgentAccess() {
        let tools = AgentTools(library: library, files: presentationFiles)
        tools.pdfFolder = { [weak self] in self?.mcp.folder }
        tools.didChange = { [weak self] id in
            guard let self, self.session.gate.isVisible, self.session.script.id == id,
                  let script = self.library.scripts.first(where: { $0.id == id }) else { return }
            self.session.pause(); self.session.present(script)
        }
        tools.select = { [weak self] id in self?.library.selectedID = id }
        tools.exportDocument = { [weak self] script in
            guard let self else { throw AgentTools.Failure("macprompter ist nicht bereit.") }
            return try self.documentData(for: script)
        }
        tools.importDocument = { [weak self] data in
            guard let self else { throw AgentTools.Failure("macprompter ist nicht bereit.") }
            return try await self.importDocument(data, select: false)
        }
        mcp.tools = tools
        #if DEBUG
        // End-to-end checks with a real MCP client without touching the user's settings.
        if let port = UserDefaults.standard.string(forKey: "MCPDebugPort").flatMap(UInt16.init) { return mcp.configure(enabled: true, port: port) }
        #endif
        mcp.configure(enabled: preferences.value.mcpEnabled, port: preferences.value.mcpPort)
    }
}
