import Foundation
import Observation

@MainActor @Observable
final class ScriptLibrary {
    var scripts: [Script] = []
    var selectedID: UUID?
    var errorMessage: String?
    private var pendingSave: Task<Void, Never>?
    private var canSave = true
    let fileURL: URL

    var selected: Script? { scripts.first { $0.id == selectedID } }

    init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "macprompter", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "scripts.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                scripts = try JSONDecoder().decode([Script].self, from: Data(contentsOf: fileURL))
                // The body of a presentation is derived; refresh it when the cue format changed.
                for index in scripts.indices {
                    if let deck = scripts[index].presentation { scripts[index].body = PresentationComposer.compose(deck).body }
                }
            }
            catch {
                canSave = false
                errorMessage = "Die Skriptbibliothek konnte nicht geladen werden. Die Originaldatei bleibt unverändert: \(fileURL.path)"
            }
        }
        selectedID = scripts.first?.id
    }

    @discardableResult
    func add(title: String = "Neues Skript", body: String = "", language: SpeechLanguage = .german, presentation: PresentationDeck? = nil, select: Bool = true) -> UUID {
        var script = Script(title: title, body: body, language: language)
        if let presentation {
            script.presentation = presentation
            script.body = PresentationComposer.compose(presentation).body
        }
        scripts.insert(script, at: 0)
        if select || selectedID == nil { selectedID = script.id }
        scheduleSave()
        return script.id
    }

    /// Updates the selected script, or the script with `id` (agents edit any script).
    func update(id: UUID? = nil, title: String? = nil, body: String? = nil, language: SpeechLanguage? = nil) {
        guard let index = scripts.firstIndex(where: { $0.id == (id ?? selectedID) }) else { return }
        if let title { scripts[index].title = title }
        if let body { scripts[index].body = body }
        if let language { scripts[index].language = language }
        scripts[index].modifiedAt = Date()
        scheduleSave()
    }

    func duplicate(presentation: PresentationDeck? = nil) {
        guard let script = selected else { return }
        var copy = script
        copy.id = UUID(); copy.title += " – Kopie"; copy.modifiedAt = Date()
        if let presentation { copy.presentation = presentation }
        scripts.insert(copy, at: 0); selectedID = copy.id; scheduleSave()
    }

    /// Remembers the side-pane settings of a script; no modification date
    /// change, since the script itself did not change.
    func setSettings(_ settings: ScriptSettings, for id: UUID?) {
        guard let index = scripts.firstIndex(where: { $0.id == id }), scripts[index].settings != settings else { return }
        scripts[index].settings = settings
        scheduleSave()
    }

    /// Adds an imported script under a fresh id so it never replaces an existing one.
    @discardableResult
    func insert(_ script: Script, select: Bool = true) -> UUID {
        var script = script
        script.id = UUID()
        scripts.insert(script, at: 0)
        if select || selectedID == nil { selectedID = script.id }
        scheduleSave()
        return script.id
    }

    /// Stores a changed deck and re-derives the prompter text from it.
    func updatePresentation(_ deck: PresentationDeck?, for id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        if let deck {
            scripts[index].body = PresentationComposer.compose(deck).body
        } else if let old = scripts[index].presentation {
            scripts[index].body = old.plainText
        }
        scripts[index].presentation = deck
        scripts[index].modifiedAt = Date()
        scheduleSave()
    }

    func deleteSelected() {
        scripts.removeAll { $0.id == selectedID }
        selectedID = scripts.first?.id
        scheduleSave()
    }

    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        pendingSave?.cancel()
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(scripts).write(to: fileURL, options: .atomic)
        } catch { errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)" }
    }
}
