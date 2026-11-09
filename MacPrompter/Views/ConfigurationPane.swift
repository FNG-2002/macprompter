import SwiftUI

struct ConfigurationPane: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                previewCard
                Label("Diese Einstellungen gelten für dieses Skript und werden in macprompter-Dateien mitgesichert.", systemImage: "doc.badge.gearshape")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                section("STEUERUNG") {
                    Picker("Steuerung", selection: $model.preferences.value.mode) {
                        ForEach(PlaybackMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented).labelsHidden().controlSize(.large)
                    Text(modeDescription).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.preferences.value.mode == .voice {
                        SpeechLanguagePicker(model: model)
                        Label("Lokale Spracherkennung", systemImage: "lock").font(.system(size: 11)).foregroundStyle(Design.accent)
                    }
                    if model.preferences.value.mode == .automatic {
                        ValueSlider(title: "Tempo", value: $model.preferences.value.speed, range: 10...120, suffix: "pt/s")
                    }
                }
                if model.library.selected?.presentation != nil {
                    section("PRÄSENTATION") {
                        PresentationDisplayPicker(model: model)
                        Toggle("Referentenansicht auf dem Prompter-Bildschirm", isOn: $model.preferences.value.presenterView)
                            .toggleStyle(.switch).controlSize(.mini)
                        Text("Folien wechseln, sobald ihr Text gelesen ist. ← → oder ⌥⌘← → wechseln manuell, der Prompter springt mit.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("LESEKOMFORT") {
                    FontTiles(font: $model.preferences.value.font)
                    FontSizeTiles(size: $model.preferences.value.fontSize, font: model.preferences.value.font)
                    ValueSlider(title: "Textgröße", value: $model.preferences.value.fontSize, range: 18...56, suffix: "pt")
                    ColorSwatches(color: $model.preferences.value.textColor)
                    ValueSlider(title: "Zeilenabstand", value: $model.preferences.value.lineSpacing, range: 4...28, suffix: "pt")
                    Toggle("Lesezeile hervorheben", isOn: $model.preferences.value.focusLine).toggleStyle(.switch).controlSize(.mini)
                    OpacitySlider(model: model)
                }
                section("POSITION") {
                    Picker("Position", selection: $model.preferences.value.docked) {
                        Text("An der Notch").tag(true)
                        Text("Frei verschiebbar").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)
                    DisplayPicker(model: model)
                    ValueSlider(title: "Breite", value: $model.preferences.value.width, range: Preferences.widthRange, suffix: "pt")
                    ValueSlider(title: "Höhe", value: $model.preferences.value.height, range: Preferences.heightRange, suffix: "pt")
                }
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "cursorarrow.motionlines").foregroundStyle(Design.accent)
                    Text("Maus darüber? Alles pausiert. Sobald du sie wegbewegst, geht es weiter.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(12).background(Design.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                Button { model.showSettings() } label: {
                    HStack { Text("Weitere Einstellungen"); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 32)
        }.background(Design.surface.opacity(0.32))
    }

    private var modeDescription: String {
        switch model.preferences.value.mode {
        case .voice: "Dein Text folgt deiner Stimme und wartet, wenn du pausierst."
        case .automatic: "Gleichmäßiges Scrollen in deinem Tempo."
        case .manual: "Mit ⌥⌘↓ vorwärts und ⌥⌘↑ zurück. Hover hält die Navigation an."
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Vorschau", systemImage: "viewfinder")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("NOTCH").font(.system(size: 9, weight: .semibold)).tracking(1)
                    .foregroundStyle(.tertiary)
            }.foregroundStyle(.secondary)
            GeometryReader { geometry in
                let p = model.preferences.value
                // The preview is narrower than the prompter: scale type by the
                // same factor (at least half, to stay readable), so line breaks
                // match what the prompter shows.
                let textWidth = max(1, geometry.size.width - 28 - 44)
                let scale = min(1, max(0.5, textWidth / max(1, p.width - 52 - 24)))
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(
                        colors: [Color(red: 0.23, green: 0.25, blue: 0.32), Color(red: 0.13, green: 0.14, blue: 0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 12) {
                        Capsule().fill(.white.opacity(0.16)).frame(width: 36, height: 3).padding(.top, 10)
                        Text(AttributedString(ScriptStyle.preview(previewText, preferences: p, scale: scale)))
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.2), value: p.fontSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: model.preferences.value.mirror ? -1 : 1, y: 1)
                            .padding(.horizontal, 22)
                            .frame(height: 128, alignment: .top)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        Spacer(minLength: 0)
                    }
                    .frame(width: max(1, geometry.size.width - 28), height: 176)
                    .background(.black.opacity(model.preferences.value.prompterOpacity), in: NotchShape())
                }
            }.frame(height: 194)
            Text("Deine Worte. Direkt bei der Kamera.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var previewText: String {
        let text = model.library.selected?.body ?? "Deine nächste Geschichte beginnt hier."
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            content()
        }.font(.system(size: 13))
    }
}

/// All languages of Apple's on-device dictation, plus a one-click switch
/// when the script is clearly written in another language.
struct SpeechLanguagePicker: View {
    @Bindable var model: AppModel
    @State private var languages: [SpeechLanguage] = [.german, .english]
    @State private var suggestion: SpeechLanguage?
    var body: some View {
        let current = model.library.selected?.language ?? .german
        VStack(alignment: .leading, spacing: 8) {
            Picker("Sprache", selection: Binding(get: { current }, set: { model.updateScript(language: $0) })) {
                ForEach(languages.contains(current) ? languages : [current] + languages) { Text($0.title).tag($0) }
            }.controlSize(.regular)
            if let suggestion {
                Button { model.updateScript(language: suggestion) } label: {
                    Label("Text klingt nach \(suggestion.shortTitle) · übernehmen", systemImage: "character.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Design.accent)
                .help("Die Spracherkennung auf die Sprache des Skripts umstellen")
            }
        }
        .task { languages = await SpeechLanguage.available() }
        .task(id: "\(model.library.selected?.body.prefix(6000) ?? "")|\(current.rawValue)|\(languages.count)") {
            let text = model.library.selected?.body ?? ""
            let candidates = languages
            suggestion = await Task.detached { SpeechLanguage.suggestion(for: text, current: current, among: candidates) }.value
        }
    }
}

/// Font choice as tiles showing each typeface.
struct FontTiles: View {
    @Binding var font: ReadingFont
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ReadingFont.allCases) { option in
                Tile(selected: font == option) { font = option } content: {
                    Text("Ag").font(Font(option.nsFont(size: 17))).frame(height: 22)
                    Text(option.title).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }.help(option == .openDyslexic ? "OpenDyslexic – Schrift für Menschen mit Legasthenie" : option.title)
            }
        }
    }
}

/// Quick sizes; the slider below stays for exact values.
struct FontSizeTiles: View {
    @Binding var size: Double
    let font: ReadingFont
    static let presets: [(title: String, size: Double)] = [("S", 24), ("M", 32), ("L", 40), ("XL", 48)]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets, id: \.title) { preset in
                Tile(selected: size == preset.size) { size = preset.size } content: {
                    Text("Ag").font(Font(font.nsFont(size: preset.size * 0.42)))
                        .frame(height: 22)
                    Text(preset.title).font(.system(size: 9.5, weight: .medium))
                }.help("\(Int(preset.size)) pt")
            }
        }
    }
}

struct ColorSwatches: View {
    @Binding var color: ReadingColor
    var body: some View {
        HStack(spacing: 0) {
            Text("Textfarbe").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                ForEach(ReadingColor.allCases) { option in
                    Button { color = option } label: {
                        Circle().fill(option.color).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(color == option ? Design.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain).help(option.title).accessibilityLabel("Textfarbe \(option.title)")
                    .accessibilityAddTraits(color == option ? .isSelected : [])
                }
            }
        }
    }
}

private struct Tile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            VStack(spacing: 4) { content }
                .foregroundStyle(selected ? Design.accent : .primary)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Design.accent.opacity(0.13) : Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Design.accent.opacity(0.45) : .clear, lineWidth: 1.2))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value)) \(suffix)").monospacedDigit()
            }.font(.system(size: 12))
            Slider(value: $value, in: range, step: 1).controlSize(.regular).accessibilityLabel(title)
        }
    }
}

struct DisplayPicker: View {
    @Bindable var model: AppModel
    @State private var screens = NSScreen.screens
    var body: some View {
        Picker("Bildschirm", selection: $model.preferences.value.displayID) {
            Text("Automatisch · Notch bevorzugt").tag(UInt32(0))
            ForEach(screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
            if model.preferences.value.displayID != 0 && !screens.contains(where: { $0.displayID == model.preferences.value.displayID }) {
                Text("Nicht verbunden · automatisch").tag(model.preferences.value.displayID)
            }
        }
        .controlSize(.small)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }
}

struct PresentationDisplayPicker: View {
    @Bindable var model: AppModel
    @State private var screens = NSScreen.screens
    var body: some View {
        Picker("Folien auf", selection: $model.preferences.value.presentationDisplayID) {
            Text("Automatisch · zweiter Bildschirm").tag(UInt32(0))
            ForEach(screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
            if model.preferences.value.presentationDisplayID != 0 && !screens.contains(where: { $0.displayID == model.preferences.value.presentationDisplayID }) {
                Text("Nicht verbunden · automatisch").tag(model.preferences.value.presentationDisplayID)
            }
        }
        .controlSize(.small)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }
}

/// Background opacity in percent; lets slides or other content show through.
struct OpacitySlider: View {
    @Bindable var model: AppModel
    var body: some View {
        ValueSlider(title: "Deckkraft Hintergrund", value: Binding(
            get: { (model.preferences.value.prompterOpacity * 100).rounded() },
            set: { model.preferences.value.prompterOpacity = $0 / 100 }), range: 20...100, suffix: "%")
    }
}
