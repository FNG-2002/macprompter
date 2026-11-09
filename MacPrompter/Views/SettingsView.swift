import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var tab: SettingsTab? = .reading
    @State private var history: [SettingsTab] = [.reading]
    @State private var historyIndex = 0
    @State private var navigating = false
    @State private var diagnostics = SpeechLatencySummary([])
    @State private var audioBlock: Double?
    @State private var speechStart: Double?
    @State private var speechStartMicrophone: Double?
    @State private var recognizer: String?
    @State private var semanticReturns = 0
    enum SettingsTab: String, CaseIterable, Identifiable {
        case reading = "Lesen", control = "Steuerung", remote = "iPhone-Fernbedienung", agents = "KI-Agenten", diagnostics = "Diagnose", privacy = "Privatsphäre", about = "Über macprompter"
        var id: Self { self }
        var symbol: String {
            switch self { case .reading: "textformat.size"; case .control: "keyboard"; case .remote: "iphone.radiowaves.left.and.right"; case .agents: "point.3.connected.trianglepath.dotted"; case .diagnostics: "waveform.path.ecg"; case .privacy: "hand.raised"; case .about: "info.circle" }
        }
    }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $tab) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                .listStyle(.sidebar).scrollEdgeEffectStyle(.soft, for: .all)
                .frame(width: 190)
                .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190).toolbar(removing: .sidebarToggle)
                .navigationTitle("Einstellungen")
        } detail: {
            Form {
                switch tab ?? .reading {
                case .reading: reading
                case .control: control
                case .remote: RemoteSettingsSections(remote: model.remote, isEnabled: $model.preferences.value.remoteControlEnabled)
                case .agents: MCPSettingsSections(mcp: model.mcp, isEnabled: $model.preferences.value.mcpEnabled, port: $model.preferences.value.mcpPort)
                case .diagnostics: diagnosticsTab
                case .privacy: privacy
                case .about: about
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle((tab ?? .reading).rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }.disabled(historyIndex == 0).help("Zurück")
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }.disabled(historyIndex >= history.count - 1).help("Vorwärts")
            }
        }
        .onChange(of: tab) { _, next in
            guard !navigating, let next, history[historyIndex] != next else { return }
            history = Array(history.prefix(historyIndex + 1)) + [next]
            historyIndex += 1
        }
        .tint(Design.accent)
    }
    @ViewBuilder private var diagnosticsTab: some View {
        Section("Satzmodelle für Umformulierungen") {
            LabeledContent("Deutsch", value: modelAvailability(model.session.semanticGermanAvailable))
            LabeledContent("Englisch", value: modelAvailability(model.session.semanticEnglishAvailable))
            Label("Verarbeitung vollständig auf deinem Mac", systemImage: "lock.shield")
                .font(.callout)
            Text("Die Satzmodelle helfen beim Wiederfinden, wenn du leicht vom Skript abweichst. Sie greifen nur ein, wenn die normale Wortverfolgung keinen Anschluss findet. Keine Audio-Uploads und kein Cloud-Fallback. Fehlt ein Modell, bleibt die normale Sprachführung aktiv.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await model.session.checkSemanticModels() }
        speechDiagnostics
    }

    @ViewBuilder private var speechDiagnostics: some View {
        Section("Sprachdiagnose · letzter Take") {
            if diagnostics.events == 0 {
                Text("Noch keine Messwerte. Starte einen Take im Modus Stimme; die Werte erscheinen hier, auch während du sprichst.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LabeledContent("Erkennungsereignisse", value: "\(diagnostics.events) · \(Int((Double(diagnostics.advanced) / Double(diagnostics.events) * 100).rounded())) % mit Fortschritt")
                if let recognizer { LabeledContent("Erkenner", value: recognizer) }
                LabeledContent("Wortende → erkannt", value: Self.format(diagnostics.word, digits: 0))
                LabeledContent("Neue Wörter alle", value: Self.format(diagnostics.newWords, digits: 0))
                LabeledContent("Rückkehr per Satzmodell", value: "\(semanticReturns)")
                if diagnostics.wordsOnlyInFinal > 0 {
                    LabeledContent("Erst im finalen Ergebnis", value: "\(diagnostics.wordsOnlyInFinal) Wörter")
                }
                LabeledContent("Erkennung (Audioende → Ergebnis)", value: Self.format(diagnostics.recognition, digits: 0))
                LabeledContent("Davon ab 1 Sekunde", value: "\(diagnostics.slowRecognitions)")
                LabeledContent("Wortzuordnung", value: Self.format(diagnostics.tracker, digits: 2))
                LabeledContent("Markierung angewendet", value: Self.format(diagnostics.highlight, digits: 1))
                LabeledContent("Revidierte Teilresultate", value: "\(diagnostics.revised)")
                LabeledContent("Ohne Fortschritt") {
                    Text(Self.outcomes(diagnostics.outcomes)).multilineTextAlignment(.trailing)
                }
            }
            if let audioBlock { LabeledContent("Audioblock", value: Self.milliseconds(audioBlock, digits: 1)) }
            if let speechStart {
                LabeledContent("Start der Erkennung", value: Self.milliseconds(speechStart, digits: 0)
                    + (speechStartMicrophone.map { " · davon Mikrofon \(Self.milliseconds($0, digits: 0))" } ?? ""))
            }
            Text("Nur Zeitwerte der letzten bis zu 256 Erkennungsereignisse, im Arbeitsspeicher. Keine Wörter, kein Audio, nichts wird gespeichert. Erkennungszeiten sind Schätzungen aus den Zeitstempeln des Erkenners, nicht die Verzögerung bis zum Bildschirm. „Wortende → erkannt“ misst pro Wort, wie lange nach seinem Ende es zum ersten Mal erscheint (aus den Wortzeiten der finalen Ergebnisse). „Neue Wörter alle“ ist der Takt, in dem der Erkenner neue Wörter liefert.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            // Metrics are deliberately not observable (speech-rate updates).
            while !Task.isCancelled {
                diagnostics = model.session.speechLatency.summary
                audioBlock = model.session.speech.audioBlockMilliseconds
                speechStart = model.session.speech.startMilliseconds
                speechStartMicrophone = model.session.speech.startMicrophoneMilliseconds
                recognizer = model.session.speech.recognizerTitle
                semanticReturns = model.session.speechLatency.semanticReturns
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func format(_ spread: SpeechLatencySummary.Spread?, digits: Int) -> String {
        guard let spread else { return "–" }
        return "Median \(milliseconds(spread.median, digits: digits)) · p95 \(milliseconds(spread.p95, digits: digits))"
    }

    private static func outcomes(_ counts: [SpeechEventOutcome: Int]) -> String {
        let labels: [(SpeechEventOutcome, String)] = [(.unknownWord, "Wort nicht im Skript"), (.ambiguous, "noch nicht eindeutig"), (.offScript, "Einschub"),
            (.duplicate, "Wiederholung"), (.revision, "Revision"), (.nothingNew, "nichts Neues"), (.paused, "pausiert")]
        let parts = labels.compactMap { outcome, label in counts[outcome].map { "\(label) \($0)" } }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    private static func milliseconds(_ value: Double, digits: Int) -> String {
        "\(value.formatted(.number.precision(.fractionLength(digits)))) ms"
    }

    private func modelAvailability(_ available: Bool?) -> String {
        guard let available else { return "Wird geprüft …" }
        return available ? "Lokal verfügbar" : "Nicht verfügbar"
    }

    private func navigate(_ delta: Int) {
        navigating = true; historyIndex += delta; tab = history[historyIndex]
        DispatchQueue.main.async { navigating = false }
    }

    @ViewBuilder private var reading: some View {
        Section("Typografie") {
            Picker("Schrift", selection: $model.preferences.value.font) {
                ForEach(ReadingFont.allCases) { Text($0.title).tag($0) }
            }
            ValueSlider(title: "Textgröße", value: $model.preferences.value.fontSize, range: 18...56, suffix: "pt")
            Picker("Textfarbe", selection: $model.preferences.value.textColor) {
                ForEach(ReadingColor.allCases) { Text($0.title).tag($0) }
            }
            ValueSlider(title: "Zeilenabstand", value: $model.preferences.value.lineSpacing, range: 4...28, suffix: "pt")
            Text("„Dyslexie“ nutzt OpenDyslexic, eine zusätzliche Leseoption. Wähle die Schrift, die sich für dich am angenehmsten liest.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Prompter") {
            Toggle("Lesezeile hervorheben", isOn: $model.preferences.value.focusLine)
            Toggle("Horizontal spiegeln", isOn: $model.preferences.value.mirror)
            OpacitySlider(model: model)
            Text("Ein durchscheinender Hintergrund lässt Folien oder Kamera-Vorschau darunter erkennen. Der Text bleibt voll deckend.").font(.caption).foregroundStyle(.secondary)
            Text("Für die Verwendung mit einem Teleprompter-Spiegel.").font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $model.preferences.value.speechPacedScrolling) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Im Sprechtempo scrollen")
                    Text("Nur im Modus Stimme: Der Text gleitet zwischen erkannten Wörtern in deinem Tempo weiter statt zeilenweise zu springen, höchstens drei bis vier Wörter voraus. Bei einer Pause bleibt er stehen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
                .accessibilityLabel("Im Sprechtempo scrollen")
                .accessibilityHint("Bewegt den Text im Modus Stimme gleichmäßig statt zeilenweise; die Markierung bleibt auf erkannten Wörtern.")
            DisplayPicker(model: model)
        }
    }
    @ViewBuilder private var control: some View {
        Section("Start") {
            Picker("Countdown", selection: $model.preferences.value.countdownSeconds) {
                Text("Ohne Countdown").tag(0)
                Text("3 Sekunden").tag(3)
                Text("5 Sekunden").tag(5)
                Text("10 Sekunden").tag(10)
            }
            Text("Hover hält Timer, Stimme, Tastatur und Countdown an. Eine manuell gesetzte Pause bleibt nach dem Verlassen bestehen.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Scrollrad") {
            Toggle("Auch außerhalb des Prompters scrollen", isOn: $model.preferences.value.scrollWheelAnywhere)
            if model.preferences.value.scrollWheelAnywhere && !model.scrollAccessGranted {
                Text("Für das Scrollen außerhalb des Prompters braucht macprompter die Freigabe „Eingabeüberwachung“. Wirkt es danach nicht sofort, macprompter neu starten. Über dem Prompter funktioniert das Scrollrad auch ohne Freigabe.").font(.caption).foregroundStyle(.orange)
                Button("Eingabeüberwachung öffnen …") {
                    model.requestListenAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
            Text("Mausrad und Trackpad bewegen den Text in jedem Modus. Über dem Prompter bleibt die Hover-Pause bestehen und nur das Scrollrad verschiebt den Text. Außerhalb scrollt zusätzlich das Fenster unter dem Zeiger mit. macprompter liest dafür nur Scroll-Ereignisse, keine Tasten, und nur solange der Prompter sichtbar ist.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { model.refreshScrollAccess() }
        Section("Folien") {
            Toggle("Folien wechseln mit dem Lesefortschritt", isOn: $model.preferences.value.slidesFollowReading)
            Text("Läuft der Text an einer Folienmarke wie [Nächste Folie] vorbei – per Stimme, Tempo, Scrollrad, Tasten oder iPhone –, wechselt die Folie automatisch. Ausgeschaltet wechseln Folien nur per Pfeiltasten, Presenter-Fernbedienung oder iPhone; der Prompter springt dabei weiterhin mit.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Globale Tastenkürzel") {
            LabeledContent("Start / Pause", value: "⌥ ⌘ P")
            LabeledContent("Sofort ausblenden", value: "⌥ ⌘ H")
            LabeledContent("Zurück / Weiter", value: "⌥ ⌘ ↑ / ↓")
            LabeledContent("Folie zurück / weiter (beim Präsentieren)", value: "⌥ ⌘ ← / →")
            if let warning = model.shortcutWarning { Text(warning).foregroundStyle(.orange).font(.caption) }
            Text("Funktionieren auch in anderen Apps. Keine Bedienungshilfen-Freigabe nötig.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Sprache") {
            Text("Die Sprachsteuerung folgt dem Skript in Deutsch oder Englisch. Die Sprache legst du pro Skript fest. Das erste Starten kann ein Sprachmodell von Apple laden; die Erkennung selbst läuft lokal.").font(.callout)
            Button("Mikrofon-Einstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
    @ViewBuilder private var privacy: some View {
        Section("Bildschirmfreigabe") {
            Label("Kein universeller Aufnahmeschutz", systemImage: "rectangle.slash").font(.headline)
            Text("macprompter setzt den verfügbaren macOS-Fensterschutz für das Prompter-Overlay. Moderne Aufnahme- und Konferenz-Apps können den Text trotzdem erfassen. Die Skriptbibliothek und Einstellungen sind normale, sichtbare Fenster.")
            Text("Teile möglichst ein einzelnes App-Fenster. Prüfe vor deinem Termin eine Testaufnahme mit genau der App, die du verwenden willst. Mit ⌥⌘H blendest du den Prompter sofort aus.").foregroundStyle(.secondary)
            Link("Apples Erklärung zum Aufnahmeschutz", destination: URL(string: "https://developer.apple.com/forums/thread/792152")!)
        }
        Section("Deine Daten") {
            Label("Keine Konten. Keine Telemetrie. Keine Audio-Uploads.", systemImage: "lock.shield")
            Text("Skripte liegen lokal im Application-Support-Ordner. Mikrofon-Audio wird nur während der Sprachsteuerung verarbeitet und nicht gespeichert. Manuelles Pausieren und Ausblenden schalten das Mikrofon aus. Während Hover-Pausen bleibt es aktiv, damit die Erkennung sofort weitergehen kann.").font(.caption).foregroundStyle(.secondary)
            Button("Skriptordner im Finder öffnen") { NSWorkspace.shared.activateFileViewerSelecting([model.library.fileURL.deletingLastPathComponent()]) }
        }
    }
    @ViewBuilder private var about: some View {
        Section {
            Label("macprompter", systemImage: "text.viewfinder").font(.largeTitle.weight(.semibold))
            Text("Deine Worte. Dein Tempo.").foregroundStyle(.secondary)
            Text("\(AppInfo.versionLabel()) · Für macOS 26 und neuer").font(.caption)
        }
        Section("Open Source") {
            Text("macprompter ist Open Source unter der MIT-Lizenz. Updates gibt es auf GitHub; die App selbst prüft nicht online nach neuen Versionen.")
            Link("Quellcode auf GitHub", destination: AppInfo.repository)
            Link("Versionshinweise", destination: AppInfo.releases)
            Link("Problem melden", destination: AppInfo.newIssue)
        }
        Section("Entstehung") {
            Text("Entwickelt von FNG-2002. Den Code schreiben überwiegend KI-Coding-Agents (Claude Code) nach Vorgaben des Maintainers; jede Änderung muss die automatischen Tests bestehen, und er testet die App selbst im Alltag. Die App nutzt keine Cloud-KI: Spracherkennung und Satzmodelle sind lokale Apple-Frameworks.").foregroundStyle(.secondary)
        }
        Section("Software Dritter") {
            Text("OpenDyslexic von Abbie Gonzalez · SIL Open Font License 1.1")
            Button("Schriftlizenz anzeigen") {
                if let url = Bundle.main.url(forResource: "OFL", withExtension: "txt") { NSWorkspace.shared.open(url) }
            }
            Text("Notch-Form nach macos-app-skills von Fayaz Ahmed · MIT-Lizenz")
            Button("Alle Lizenzen anzeigen") { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate() }
        }
    }
}
