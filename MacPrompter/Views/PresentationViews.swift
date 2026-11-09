import AppKit
import PDFKit
import SwiftUI

/// Draws one PDF page as vectors, aspect-fit on black.
struct SlideCanvas: NSViewRepresentable {
    let page: PDFPage?
    func makeNSView(context: Context) -> PageView { PageView() }
    func updateNSView(_ view: PageView, context: Context) {
        if view.page !== page { view.page = page; view.needsDisplay = true }
    }

    final class PageView: NSView {
        var page: PDFPage?
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            bounds.fill()
            guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
            let box = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            context.saveGState()
            context.translateBy(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            // Like any PDF viewer: pages without their own background are paper white.
            context.setFillColor(.white)
            context.fill(CGRect(origin: .zero, size: size))
            page.draw(with: .cropBox, to: context)
            context.restoreGState()
        }
    }
}

struct AudienceView: View {
    let model: AppModel
    var body: some View {
        let presenter = model.presenter
        ZStack {
            Color.black.ignoresSafeArea()
            if !presenter.blackout {
                SlideCanvas(page: presenter.page(model.session.currentSlide))
            }
        }
        .accessibilityLabel(model.slideStatus?.label ?? "Präsentation")
    }
}

struct PresenterView: View {
    let model: AppModel
    let topReserve: Double
    var body: some View {
        let presenter = model.presenter
        let session = model.session
        let status = model.slideStatus
        VStack(spacing: 0) {
            Color.clear.frame(height: topReserve)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    caption("AKTUELLE FOLIE")
                    slide(presenter.blackout ? nil : presenter.page(status?.current), placeholder: "Schwarzbild")
                }
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        caption("NÄCHSTE FOLIE")
                        slide(status.flatMap { $0.current + 1 < $0.count ? presenter.page($0.current + 1) : nil }, placeholder: "Ende der Präsentation")
                            .frame(maxHeight: 200)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status?.label ?? "–")
                            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        HStack(alignment: .center, spacing: 12) {
                            TimelineView(.periodic(from: presenter.startedAt, by: 1)) { context in
                                Text(context.date.timeIntervalSince(presenter.startedAt).formattedTime)
                                    .font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                            }
                            Button { model.resetTimers() } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 24, height: 20) }
                                .help("Zeit zurücksetzen (auch im Prompter)").accessibilityLabel("Zeit zurücksetzen")
                        }
                        Label(session.stateLabel, systemImage: session.gate.isPlaying ? "waveform" : "pause.circle")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Button { presenter.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 24) }
                            .help("Vorherige Folie · ←").disabled((status?.current ?? 0) == 0)
                        Button { presenter.step(1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 24) }
                            .help("Nächste Folie · →").disabled(status.map { $0.current + 1 >= $0.count } ?? true)
                        Button { model.toggle() } label: {
                            Label(session.gate.isPlaying || session.isPreparing ? "Pausieren" : "Take starten",
                                  systemImage: session.gate.isPlaying || session.isPreparing ? "pause.fill" : "play.fill")
                        }.help("Prompter starten oder pausieren · ⌥⌘P")
                    }.controlSize(.large)
                    HStack(spacing: 10) {
                        Toggle("Schwarzbild", isOn: Binding(get: { presenter.blackout }, set: { model.presenter.blackout = $0 }))
                            .toggleStyle(.button).help("Folien ausblenden · B")
                        Button("Beenden", role: .destructive) { presenter.end() }.help("Präsentation beenden · Esc")
                    }
                    Text("← → oder Presenter-Fernbedienung wechseln Folien. Der Prompter springt mit.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(width: 320)
            }
            .padding(.horizontal, 32).padding(.vertical, 26)
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(Design.canvas)
        .preferredColorScheme(.dark)
        .tint(Design.accent)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
    }

    private func slide(_ page: PDFPage?, placeholder: String) -> some View {
        ZStack {
            Color.black
            if let page { SlideCanvas(page: page) } else { Text(placeholder).font(.system(size: 13)).foregroundStyle(.secondary) }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Design.border))
    }
}
