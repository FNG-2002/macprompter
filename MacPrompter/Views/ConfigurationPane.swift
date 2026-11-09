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
                        Picker("Sprache", selection: Binding(get: { model.library.selected?.language ?? .german }, set: { model.updateScript(language: $0) })) {
                            ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
                        }.controlSize(.regular)
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
                    Picker("Schrift", selection: $model.preferences.value.font) {
                        ForEach(ReadingFont.allCases) { Text($0.title).tag($0) }
                    }.controlSize(.regular)
                    ValueSlider(title: "Textgröße", value: $model.preferences.value.fontSize, range: 18...56, suffix: "pt")
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
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(
                        colors: [Color(red: 0.23, green: 0.25, blue: 0.32), Color(red: 0.13, green: 0.14, blue: 0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 12) {
                        Capsule().fill(.white.opacity(0.16)).frame(width: 36, height: 3).padding(.top, 10)
                        Text(AttributedString(ScriptStyle.attributed(previewText,
                            font: model.preferences.value.font.nsFont(size: min(22, model.preferences.value.fontSize * 0.55)), spacing: 3)))
                            .fixedSize(horizontal: false, vertical: true)
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
