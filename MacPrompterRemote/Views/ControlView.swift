import SwiftUI

struct ControlView: View {
    let client: RemoteClient
    @AppStorage("remote.layout") private var layout = RemoteLayout.all

    private var status: RemoteStatus { client.status ?? RemoteStatus() }
    private var macName: String { if case .connected(let name) = client.phase { name } else { "Mac" } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatusCard(status: status)
                if layout == .slides {
                    SlideClicker(client: client, slides: status.slides)
                } else {
                    TransportCard(client: client, status: status)
                    TempoCard(client: client, status: status)
                    ScrollCard(client: client, status: status)
                    if layout == .all { SlidesCard(client: client, slides: status.slides) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .animation(.smooth, value: layout)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(macName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Trennen", systemImage: "xmark") { client.disconnect() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ansicht", selection: $layout) {
                        ForEach(RemoteLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label("Ansicht: \(layout.title)", systemImage: layout.symbol)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: layout)
    }
}

private struct StatusCard: View {
    let status: RemoteStatus

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(status.scriptTitle.isEmpty ? "Kein Skript" : status.scriptTitle)
                    .font(.title3.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 12)
                Text(Duration.seconds(status.elapsedSeconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("Laufzeit \(status.elapsedSeconds) Sekunden")
            }
            ProgressView(value: status.progress)
                .accessibilityLabel("Fortschritt")
                .accessibilityValue("\(Int(status.progress * 100)) Prozent")
            Label(stateText, systemImage: stateSymbol)
                .font(.subheadline).foregroundStyle(status.isHovering ? Color.orange : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var stateText: String {
        if !status.isVisible { return "Prompter ausgeblendet" }
        if status.isHovering { return "Hover-Pause am Mac – Bewegung gesperrt" }
        return status.state.isEmpty ? (status.isPlaying ? "Läuft" : "Pausiert") : status.state
    }

    private var stateSymbol: String {
        if !status.isVisible { return "eye.slash" }
        if status.isHovering { return "hand.point.up.left.fill" }
        if status.countdown > 0 { return "timer" }
        return status.isPlaying ? "play.fill" : "pause.fill"
    }
}

private struct TransportCard: View {
    let client: RemoteClient
    let status: RemoteStatus
    @ScaledMetric(relativeTo: .largeTitle) private var playSize = 76.0
    @ScaledMetric(relativeTo: .title) private var sideSize = 52.0
    @State private var taps = 0

    private var running: Bool { status.isPlaying || status.isPreparing }

    var body: some View {
        Card {
            HStack(alignment: .top) {
                captioned("Ausblenden") {
                    Button { client.send(.hide); taps += 1 } label: { icon("eye.slash", size: sideSize) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(!status.isVisible)
                        .accessibilityLabel("Prompter ausblenden")
                }
                Spacer()
                captioned(running ? "Pause" : "Start") {
                    Button { client.send(running ? .pause : .start); taps += 1 } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill")
                            .font(.system(size: playSize * 0.36, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: playSize, height: playSize)
                    }
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                    .accessibilityLabel(running ? "Pausieren" : (status.isVisible ? "Fortsetzen" : "Prompter starten"))
                }
                Spacer()
                captioned("Skript") {
                    Menu {
                        Picker("Skript", selection: Binding(get: { status.scriptID }, set: { id in if let id { client.send(.selectScript(id)) } })) {
                            ForEach(client.scripts) { Text($0.title).tag(Optional($0.id)) }
                        }
                    } label: { icon("doc.text", size: sideSize) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .disabled(running || client.scripts.isEmpty)
                    .accessibilityLabel("Skript wählen")
                    .accessibilityValue(status.scriptTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }

    private func icon(_ symbol: String, size: Double) -> some View {
        Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: size, height: size)
    }

    private func captioned<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            // Same height for all three columns so the captions share a baseline.
            content().frame(height: playSize)
            Text(title).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

private struct TempoCard: View {
    let client: RemoteClient
    let status: RemoteStatus
    @State private var speed = 36.0
    @State private var editing = false

    var body: some View {
        Card(title: "Tempo") {
            Picker("Modus", selection: Binding(get: { status.mode }, set: { client.send(.setMode($0)) })) {
                ForEach(RemoteMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if status.mode == .automatic {
                HStack(spacing: 12) {
                    Button("Langsamer", systemImage: "tortoise.fill") { change(by: -4) }
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                    Slider(value: $speed, in: RemoteProtocol.speedRange, step: 1) { editing in
                        self.editing = editing
                        if !editing { client.send(.setSpeed(speed)) }
                    }
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(Int(speed)) Punkte pro Sekunde")
                    Button("Schneller", systemImage: "hare.fill") { change(by: 4) }
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                }
                Text("\(Int(speed)) pt/s").font(.headline).monospacedDigit()
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
            } else {
                Text(status.mode == .voice
                     ? "Im Modus Stimme folgt der Text deiner Stimme. Das Tempo gilt nur im Modus Automatisch."
                     : "Im Modus Manuell bewegst du den Text selbst – mit den Pfeilen oder der Scrollfläche.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { speed = status.speed }
        .onChange(of: status.speed) { _, value in if !editing { speed = value } }
        .onChange(of: speed) { _, value in if editing { client.send(.setSpeed(value)) } }
        .sensoryFeedback(.selection, trigger: Int(speed))
    }

    private func change(by delta: Double) {
        speed = min(RemoteProtocol.speedRange.upperBound, max(RemoteProtocol.speedRange.lowerBound, speed + delta))
        client.send(.setSpeed(speed))
    }
}

private struct ScrollCard: View {
    let client: RemoteClient
    let status: RemoteStatus
    @State private var steps = 0
    @State private var fullScreen = false

    var body: some View {
        Card {
            HStack {
                Text("Manuell scrollen").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Vollbild", systemImage: "arrow.up.left.and.arrow.down.right") { fullScreen = true }
                    .labelStyle(.iconOnly).font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("Scrollfläche im Vollbild öffnen")
            }
            HStack(spacing: 12) {
                VStack(spacing: 12) {
                    ScrollStepButton(client: client, status: status, up: true, steps: $steps)
                    ScrollStepButton(client: client, status: status, up: false, steps: $steps)
                }
                ScrollPad(client: client, status: status).frame(minHeight: 120)
            }
            if let hint = status.scrollHint { Label(hint, systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: steps)
        .fullScreenCover(isPresented: $fullScreen) { FullScreenScroll(client: client) }
    }
}

/// Large scroll surface for correcting voice following with the phone in
/// hand or lying in front of the speaker. Keeps the screen awake while open.
private struct FullScreenScroll: View {
    let client: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var steps = 0
    @State private var taps = 0

    private var status: RemoteStatus { client.status ?? RemoteStatus() }
    private var running: Bool { status.isPlaying || status.isPreparing }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button("Schließen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.scriptTitle.isEmpty ? "Kein Skript" : status.scriptTitle).font(.headline).lineLimit(1)
                    Text(status.scrollHint ?? (status.state.isEmpty ? (running ? "Läuft" : "Pausiert") : status.state))
                        .font(.footnote).foregroundStyle(status.isHovering ? Color.orange : Color.secondary).lineLimit(1)
                }
                Spacer()
                Button { client.send(running ? .pause : .start); taps += 1 } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill").font(.title3.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .accessibilityLabel(running ? "Pausieren" : "Fortsetzen")
            }
            ScrollStepButton(client: client, status: status, up: true, steps: $steps, wide: true)
            ScrollPad(client: client, status: status).frame(maxHeight: .infinity)
            ScrollStepButton(client: client, status: status, up: false, steps: $steps, wide: true)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.impact(weight: .light), trigger: steps)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: client.isConnected) { _, connected in if !connected { dismiss() } }
    }
}

private struct ScrollStepButton: View {
    let client: RemoteClient
    let status: RemoteStatus
    let up: Bool
    @Binding var steps: Int
    var wide = false

    var body: some View {
        Button(up ? "Zurück" : "Weiter", systemImage: up ? "chevron.up" : "chevron.down") {
            client.send(.nudge(up ? -RemoteProtocol.stepPoints : RemoteProtocol.stepPoints)); steps += 1
        }
        .labelStyle(.iconOnly).font(.title3.weight(.semibold))
        .frame(minWidth: 44, maxWidth: wide ? .infinity : nil, minHeight: wide ? 56 : 44)
        .modifier(StepShape(wide: wide))
        .disabled(!status.canScroll)
    }

    private struct StepShape: ViewModifier {
        let wide: Bool
        func body(content: Content) -> some View {
            if wide { content.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 22)) }
            else { content.buttonStyle(.glass).buttonBorderShape(.circle) }
        }
    }
}

private struct ScrollPad: View {
    let client: RemoteClient
    let status: RemoteStatus
    @State private var accumulator = RemoteScrollAccumulator()
    @State private var lastY: Double?

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw").font(.title2)
                    Text("Wischen zum Scrollen").font(.footnote)
                }.foregroundStyle(.secondary)
            }
            .opacity(status.canScroll ? 1 : 0.45)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard status.canScroll else { return }
                let y = value.location.y
                defer { lastY = y }
                guard let lastY else { return }
                if let points = accumulator.add(y - lastY, at: value.time.timeIntervalSinceReferenceDate) { client.send(.nudge(points)) }
            }.onEnded { value in
                if let points = accumulator.flush(at: value.time.timeIntervalSinceReferenceDate, force: true), status.canScroll {
                    client.send(.nudge(points))
                }
                lastY = nil
            })
            .accessibilityElement()
            .accessibilityLabel("Scrollfläche")
            .accessibilityHint("Nach oben oder unten wischen, um den Text zu bewegen.")
            .accessibilityAdjustableAction { direction in
                guard status.canScroll else { return }
                client.send(.nudge(direction == .increment ? RemoteProtocol.stepPoints : -RemoteProtocol.stepPoints))
            }
    }
}

private struct SlidesCard: View {
    let client: RemoteClient
    let slides: RemoteSlides?
    @State private var taps = 0

    var body: some View {
        Card(title: "Folien") {
            HStack(spacing: 12) {
                slideButton("Vorherige Folie", symbol: "chevron.left", delta: -1)
                Text(counter).font(.headline).monospacedDigit().frame(maxWidth: .infinity)
                    .accessibilityLabel(slides == nil ? "Keine Präsentation" : counter)
                slideButton("Nächste Folie", symbol: "chevron.right", delta: 1)
            }
            SlideFooter(client: client, slides: slides)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }

    private var counter: String {
        guard let slides else { return "–" }
        return slides.label
    }

    private func slideButton(_ title: String, symbol: String, delta: Int) -> some View {
        Button(title, systemImage: symbol) { client.send(.stepSlide(delta)); taps += 1 }
            .labelStyle(.iconOnly).font(.title2.weight(.semibold))
            .frame(minWidth: 52, minHeight: 52)
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .disabled(slides == nil)
    }
}

private struct SlideFooter: View {
    let client: RemoteClient
    let slides: RemoteSlides?

    var body: some View {
        if let slides {
            Button(slides.isPresenting ? "Präsentation beenden" : "Präsentation starten",
                   systemImage: slides.isPresenting ? "stop.fill" : "play.rectangle.fill") {
                client.send(slides.isPresenting ? .endPresentation : .startPresentation)
            }
            .buttonStyle(.glass).frame(maxWidth: .infinity)
        } else {
            Label("Keine Präsentation geöffnet. Wähle am Mac ein Skript mit PDF-Folien.", systemImage: "rectangle.slash")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Full-height clicker for the "Nur Folien" layout: a big next target and a smaller back target.
private struct SlideClicker: View {
    let client: RemoteClient
    let slides: RemoteSlides?
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 14) {
            Text(slides?.label ?? "Keine Präsentation")
                .font(.title2.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
            target("Vorherige Folie", symbol: "chevron.left", delta: -1, height: 120)
            target("Nächste Folie", symbol: "chevron.right", delta: 1, height: 260)
            SlideFooter(client: client, slides: slides)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: taps)
    }

    @ViewBuilder private func target(_ title: String, symbol: String, delta: Int, height: CGFloat) -> some View {
        let button = Button { client.send(.stepSlide(delta)); taps += 1 } label: {
            Label(title, systemImage: symbol)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: height)
        }
        // "Next" is the primary action of a clicker.
        if delta > 0 {
            button.buttonStyle(.glassProminent).buttonBorderShape(.roundedRectangle(radius: 32)).disabled(slides == nil)
        } else {
            button.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 32)).disabled(slides == nil)
        }
    }
}
