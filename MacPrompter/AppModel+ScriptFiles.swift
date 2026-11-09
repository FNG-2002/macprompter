import AppKit
import CoreTransferable
import UniformTypeIdentifiers

/// `.macprompter` files: back up, send and re-import a script with its slides,
/// PDF and side-pane settings. Imports always create a new script.
extension AppModel {
    /// The settings a script is shown with right now.
    func settings(for script: Script) -> ScriptSettings {
        script.id == library.selectedID ? preferences.value.scriptSettings : (script.settings ?? preferences.value.scriptSettings)
    }

    func documentData(for script: Script) throws -> Data { try shareItem(for: script).encoded() }

    func shareItem(for script: Script) -> ScriptFileExport {
        ScriptFileExport(script: script, settings: settings(for: script), pdfURL: script.presentation.map(presentationFiles.storedURL))
    }

    @discardableResult
    func importDocument(_ data: Data, select: Bool = true) async throws -> UUID {
        let id = library.insert(try await Self.prepareImport(data, files: presentationFiles), select: select)
        if select { applySelectedSettings() }
        return id
    }

    /// Decodes a file and stores its PDF as a new library copy; the caller inserts the script.
    static func prepareImport(_ data: Data, files: PresentationFiles) async throws -> Script {
        let document = try ScriptDocument.decode(data)
        var script = document.script
        script.settings = script.settings?.clamped
        if var deck = script.presentation, let pdf = document.pdf {
            let pages = try await Task.detached(priority: .userInitiated) { try PresentationFiles.fingerprints(of: pdf) }.value
            deck.id = UUID(); deck.bookmark = nil; deck.fileModifiedAt = nil; deck.fileSize = nil
            // Realigns the slides should the embedded PDF not match the deck exactly.
            if deck.pages.map(\.text) != pages.map(\.text) { deck.adopt(pages: pages) }
            try files.write(pdf, for: deck)
            script.presentation = deck
            script.body = PresentationComposer.compose(deck).body
        }
        return script
    }

    func saveScriptFile() {
        guard let script = library.selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.macprompterScript]
        panel.nameFieldStringValue = ScriptDocument.fileName(for: script.title)
        panel.message = "Sichert Text, Folien samt PDF und die Einstellungen dieses Skripts in einer Datei."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do { try self.documentData(for: script).write(to: url, options: .atomic) }
                catch { self.library.errorMessage = "Sichern fehlgeschlagen: \(error.localizedDescription)" }
            }
        }
    }

    /// Finder double-click, drag onto the Dock icon or ⌘O.
    func openScriptFiles(_ urls: [URL]) {
        Task {
            for url in urls where url.pathExtension.lowercased() == ScriptDocument.fileExtension {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { try await importDocument(try Data(contentsOf: url)) }
                catch { library.errorMessage = "„\(url.lastPathComponent)“ konnte nicht geöffnet werden: \(error.localizedDescription)" }
            }
            openLibraryWindow?()
            NSApp.activate()
        }
    }

    /// Restores the side-pane settings remembered by the selected script.
    func applySelectedSettings() {
        guard let settings = library.selected?.settings?.clamped, settings != preferences.value.scriptSettings else { return }
        preferences.value.scriptSettings = settings
    }

    func observeSelection() {
        withObservationTracking { _ = library.selectedID } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applySelectedSettings()
                self.observeSelection()
            }
        }
    }
}

/// Plain values only, so the file is encoded lazily (when the user actually
/// shares) and safely off the main actor.
struct ScriptFileExport: Transferable, Sendable {
    let script: Script
    let settings: ScriptSettings
    let pdfURL: URL?

    var name: String { ScriptDocument.fileName(for: script.title) }

    func encoded() throws -> Data {
        try ScriptDocument(script: script, settings: settings, pdf: pdfURL.map { try Data(contentsOf: $0) }).encoded()
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .macprompterScript) { item in
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let file = url.appending(path: item.name)
            try item.encoded().write(to: file, options: .atomic)
            return SentTransferredFile(file)
        }
    }
}
