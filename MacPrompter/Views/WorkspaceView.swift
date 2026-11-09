import SwiftUI

// Quiet surfaces and a single accent keep the script as the visual focal point.
enum Design {
    static let accent = Color(red: 0.72, green: 0.67, blue: 1)
    static let canvas = Color(red: 0.075, green: 0.08, blue: 0.095)
    static let surface = Color(red: 0.11, green: 0.115, blue: 0.135)
    static let border = Color.white.opacity(0.07)
}

struct WorkspaceView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var deleteConfirmation = false
    @State private var showPrivacyInfo = false
    @State private var detachConfirmation = false
    @Environment(\.openWindow) private var openWindow
    var filtered: [Script] {
        model.library.scripts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider().overlay(Design.border)
                if let script = model.library.selected {
                    HStack(spacing: 0) {
                        if let deck = script.presentation {
                            SlideEditorView(model: model, script: script, deck: deck).id(script.id)
                        } else {
                            editor(script)
                        }
                        Divider().overlay(Design.border)
                        ConfigurationPane(model: model).frame(width: 360)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Platz für deine nächste Geschichte", systemImage: "text.page")
                    } description: {
                        Text("Erstelle ein Skript, importiere eine Datei oder starte mit einer Vorlage.")
                    } actions: {
                        HStack {
                            Button("Neues Skript") { model.library.add() }
                            Button("Vorlage wählen …") { model.showTemplates = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                footer
            }
            .background(Design.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $model.showTemplates) { TemplateGallery(model: model) }
        .onAppear { model.openLibraryWindow = { openWindow(id: "library") } }
        .alert("Skript löschen?", isPresented: $deleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                model.deleteSelectedScript()
            }
        } message: { Text("„\(model.library.selected?.title ?? "")“ wird aus deiner Bibliothek entfernt.") }
        .alert("PDF trennen?", isPresented: $detachConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Trennen", role: .destructive) { model.detachPresentation() }
        } message: { Text("Die Texte aller Folien bleiben als normales Skript erhalten. Folienzuordnung und PDF-Kopie werden entfernt.") }
        .alert("Hinweis", isPresented: Binding(get: { model.library.errorMessage != nil || model.session.errorMessage != nil }, set: { if !$0 { model.library.errorMessage = nil; model.session.errorMessage = nil } })) {
            Button("OK") { model.library.errorMessage = nil; model.session.errorMessage = nil }
        } message: { Text(model.library.errorMessage ?? model.session.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder").font(.system(size: 22, weight: .medium)).foregroundStyle(Design.accent)
                Text("macprompter").font(.system(size: 19, weight: .semibold))
            }.padding(.horizontal, 18).padding(.top, 44).padding(.bottom, 26)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Skripte durchsuchen", text: $search).textFieldStyle(.plain).font(.system(size: 12))
            }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14)
            HStack {
                Text("DEINE SKRIPTE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.library.scripts.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 12)
            List(selection: $model.library.selectedID) {
                ForEach(filtered) { script in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: script.presentation == nil ? "doc.text" : "rectangle.on.rectangle").font(.system(size: 16)).foregroundStyle(model.library.selectedID == script.id ? Design.accent : .gray).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(script.title.isEmpty ? "Ohne Titel" : script.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text((script.presentation.map { deck in "\(deck.sections.filter { !$0.pageIDs.isEmpty }.count) Folien · " } ?? "") + "\(ScriptParser.words(in: script.body).count) Wörter · \(script.language.shortTitle)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 7).tag(script.id)
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            .overlay { if filtered.isEmpty && !search.isEmpty { Text("Keine passenden Skripte").font(.caption).foregroundStyle(.secondary) } }
            Button { model.library.add() } label: {
                Label("Neues Skript", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).padding(9)
            }.buttonStyle(.plain).foregroundStyle(Design.accent).padding(.horizontal, 14)
            Button { model.showTemplates = true } label: {
                Label("Aus Vorlage …", systemImage: "square.grid.2x2").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.bottom, 9)
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 14)
            Divider().padding(.top, 12)
            HStack {
                Button { model.showSettings() } label: { Image(systemName: "gearshape") }.help("Einstellungen")
                Text("Alles bleibt auf deinem Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
            }.buttonStyle(.plain).padding(20)
        }
        .background(Design.surface.opacity(0.6))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEIN STUDIO").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Design.accent)
                Text("Eine gute Geschichte beginnt hier.").font(.system(size: 14, weight: .medium))
            }
            Spacer()
            Menu {
                Button("Datei öffnen …") { model.importScript() }
                Button("PDF-Präsentation importieren …") { model.importPresentation() }
            } label: { Image(systemName: "square.and.arrow.down") }.menuStyle(.borderlessButton).frame(width: 30).help("Importieren")
            Menu {
                Button("Duplizieren") { model.duplicateSelectedScript() }
                Button("Sichern als macprompter-Datei …") { model.saveScriptFile() }
                if let script = model.library.selected {
                    ShareLink(item: model.shareItem(for: script), preview: SharePreview(script.title)) {
                        Label("Teilen …", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Als Text exportieren …") { model.exportScript() }
                Divider()
                if model.library.selected?.presentation == nil {
                    Button("PDF verknüpfen …") { model.attachPresentation() }
                } else {
                    Button("Neue PDF-Version wählen …") { model.replacePresentationPDF() }
                    Button("PDF trennen …") { detachConfirmation = true }
                }
                Divider()
                Button("Löschen …", role: .destructive) { deleteConfirmation = true }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).disabled(model.library.selected == nil)
            if model.library.selected?.presentation != nil {
                Button { model.isPresenting ? model.endPresentation() : model.startPresentation() } label: {
                    Label(model.isPresenting ? "Präsentation beenden" : "Präsentieren", systemImage: model.isPresenting ? "stop.fill" : "play.rectangle")
                }.buttonStyle(.bordered).help("Folien im Vollbild zeigen, Prompter folgt · Esc beendet")
            }
            Button { model.preview() } label: { Label("Vorschau", systemImage: "viewfinder") }.buttonStyle(.bordered).disabled(model.library.selected?.body.isEmpty ?? true)
            Button { model.toggle() } label: {
                Label(model.session.gate.isPlaying || model.session.isPreparing ? "Pausieren" : "Take starten", systemImage: model.session.gate.isPlaying || model.session.isPreparing ? "pause.fill" : "play.fill")
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Design.accent, in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(.black).disabled(model.library.selected.map { ScriptParser.words(in: $0.body).isEmpty } ?? true)
        }
        .controlSize(.large).padding(.horizontal, 26).padding(.top, 30).padding(.bottom, 20)
    }

    private func editor(_ script: Script) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("SKRIPT", systemImage: "text.alignleft").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Label("Lokal · automatisch speichern", systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 30).padding(.top, 28)
            TextField("Titel deines Skripts", text: Binding(get: { model.library.selected?.title ?? "" }, set: { model.updateScript(title: $0) }))
                .textFieldStyle(.plain).font(.system(size: 30, weight: .semibold)).padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 8)
            ScriptEditor(text: Binding(get: { model.library.selected?.body ?? "" }, set: { model.updateScript(body: $0) }))
                .id(script.id)
            HStack(spacing: 7) {
                Image(systemName: "theatermasks")
                Text("Regieanweisungen in [Klammern] bleiben dezent.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 18)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.session.gate.isPlaying ? .mint : .gray).frame(width: 5, height: 5)
            Text(model.session.stateLabel).lineLimit(1)
            Spacer()
            if model.session.gate.isVisible {
                Button("Ausblenden") { model.session.hide() }.buttonStyle(.plain).foregroundStyle(Design.accent)
            }
            Button { showPrivacyInfo.toggle() } label: {
                Image(systemName: "rectangle.slash").foregroundStyle(.orange.opacity(0.8))
            }
            .buttonStyle(.plain).help("Aufnahmeschutz ist eingeschränkt")
            .popover(isPresented: $showPrivacyInfo) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Aufnahmeschutz ist eingeschränkt").font(.headline)
                    Text("macOS erlaubt keinen universellen Ausschluss aus Bildschirmaufnahmen. Teste deine konkrete Aufnahme-App. Bibliothek und Einstellungen bleiben sichtbar.")
                    Text("⌥⌘H blendet den Prompter sofort aus.").foregroundStyle(.secondary)
                }.padding(20).frame(width: 330)
            }
            if let script = model.library.selected {
                let words = ScriptParser.words(in: script.body).count
                Text("\(words) Wörter").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("≈ \(max(1, Int(ceil(Double(words) / 130)))) Min. Sprechzeit").foregroundStyle(.secondary)
            }
        }.font(.system(size: 11)).padding(.horizontal, 26).padding(.vertical, 13)
            .background(Design.surface.opacity(0.65))
    }
}
