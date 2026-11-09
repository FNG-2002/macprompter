import SwiftUI

struct NotchShape: Shape {
    func path(in r: CGRect) -> Path {
        let ear: CGFloat = 12, corner: CGFloat = 24
        var p = Path()
        p.move(to: .init(x: 0, y: 0))
        p.addQuadCurve(to: .init(x: ear, y: ear), control: .init(x: ear, y: 0))
        p.addLine(to: .init(x: ear, y: r.height - corner))
        p.addQuadCurve(to: .init(x: ear + corner, y: r.height), control: .init(x: ear, y: r.height))
        p.addLine(to: .init(x: r.width - ear - corner, y: r.height))
        p.addQuadCurve(to: .init(x: r.width - ear, y: r.height - corner), control: .init(x: r.width - ear, y: r.height))
        p.addLine(to: .init(x: r.width - ear, y: ear))
        p.addQuadCurve(to: .init(x: r.width, y: 0), control: .init(x: r.width - ear, y: 0))
        p.closeSubpath()
        return p
    }
}

struct OverlayView: View {
    @Bindable var model: AppModel
    let topInset: Double
    var body: some View {
        let s = model.session
        let p = model.preferences.value
        VStack(spacing: 8) {
            Color.clear.frame(height: topInset)
            HStack(spacing: 8) {
                Circle().fill(s.gate.isPlaying && !s.gate.isHovering ? Color.mint : Color.orange).frame(width: 6, height: 6)
                Text(s.stateLabel).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer()
                if !p.docked {
                    PanelDragHandle().frame(width: 22, height: 20)
                        .overlay(Image(systemName: "hand.draw").foregroundStyle(.secondary).allowsHitTesting(false))
                        .help("Prompter verschieben")
                }
                Button { model.preferences.value.docked.toggle() } label: { Image(systemName: p.docked ? "arrow.up.left.and.arrow.down.right" : "pin") }
                    .help(p.docked ? "Frei verschieben" : "An der Notch befestigen")
                Button { s.pause(); s.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Zurück zum Anfang")
                Button { s.togglePlayback() } label: { Image(systemName: s.gate.isPlaying || s.isPreparing ? "pause.fill" : "play.fill") }
                    .help("Start / Pause · ⌥⌘P")
                Button { s.hide() } label: { Image(systemName: "xmark") }.help("Ausblenden · ⌥⌘H")
            }
            .foregroundStyle(.white.opacity(0.7)).buttonStyle(.plain).padding(.horizontal, 30)
            ZStack(alignment: .topLeading) {
                if p.focusLine {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.055))
                        .frame(height: p.fontSize * 1.5 + p.lineSpacing).padding(.horizontal, 18).padding(.top, 8)
                    Capsule().fill(Design.accent).frame(width: 3, height: p.fontSize).padding(.leading, 20).padding(.top, 18)
                }
                ReaderView(session: s, preferences: p)
                    .padding(.horizontal, 26)
                    .scaleEffect(x: p.mirror ? -1 : 1, y: 1)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.65), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                if s.gate.countdown > 0 {
                    Text("\(s.gate.countdown)").font(.system(size: 64, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9 * p.prompterOpacity))
                }
            }
            OverlayFooter(session: s, mode: p.mode) { model.resetTimers() }
        }
        .background(.black.opacity(p.prompterOpacity))
        .overlay { ResizeHandles(model: model, inset: p.docked ? 12 : 0) }
        .clipShape(p.docked ? AnyShape(NotchShape()) : AnyShape(RoundedRectangle(cornerRadius: 24)))
        // During an edge drag the pointer can briefly leave the panel; keep the pause.
        .onHover { if !model.isResizingPrompter { model.session.setHover($0) } }
        .preferredColorScheme(.dark)
        .tint(Design.accent)
    }
}

private struct OverlayFooter: View {
    var session: PrompterSession
    let mode: PlaybackMode
    let resetTime: () -> Void
    var body: some View {
        let s = session
            HStack {
                Text(s.script.title).lineLimit(1)
                Spacer()
                if let slides = s.slideStatus {
                    Label(slides.steps > 1 ? "\(slides.slide + 1)/\(slides.slideCount) · \(slides.step + 1)/\(slides.steps)" : "\(slides.slide + 1)/\(slides.slideCount)", systemImage: "rectangle.on.rectangle").monospacedDigit()
                }
                if mode == .voice {
                    Image(systemName: s.speech.isListening ? "mic.fill" : "mic.slash")
                    ProgressView(value: Double(s.speech.level)).frame(width: 38)
                }
                Text(Double(s.elapsedSeconds).formattedTime).monospacedDigit()
                Button(action: resetTime) { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.plain).help("Zeit zurücksetzen (auch in der Referentenansicht)")
                    .accessibilityLabel("Zeit zurücksetzen")
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 32).padding(.bottom, 14)
    }
}

extension Double {
    var formattedTime: String { String(format: "%02d:%02d", Int(max(0, self)) / 60, Int(max(0, self)) % 60) }
}

struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) { }
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// Strips along the side and bottom edges for resizing by drag, plus a
/// visible grabber at the bottom so the feature can be found.
private struct ResizeHandles: View {
    let model: AppModel
    let inset: Double
    static let thickness = 10.0
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                handle(.left).frame(width: Self.thickness)
                Spacer(minLength: 0)
                handle(.right).frame(width: Self.thickness)
            }.padding(.horizontal, inset).padding(.top, 40).padding(.bottom, 20)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    handle(.bottomLeft).frame(width: 22)
                    handle(.bottom)
                    handle(.bottomRight).frame(width: 22)
                }
                .frame(height: Self.thickness)
                .overlay(alignment: .center) {
                    Capsule().fill(.white.opacity(0.28)).frame(width: 40, height: 4).allowsHitTesting(false)
                }
                .padding(.horizontal, inset + 10)
            }
        }
    }
    private func handle(_ edge: ResizeEdge) -> some View {
        PanelResizeHandle(edge: edge) { start, dx, dy in model.resizePrompter(from: start, edge: edge, dx: dx, dy: dy) } start: { frame in
            model.beginPrompterResize()
            var start = model.preferences.value
            // Floating panels keep their opposite edges; start from the real frame.
            if !start.docked, let frame { start.floatingX = frame.minX; start.floatingY = frame.minY }
            return start
        } end: { model.endPrompterResize() }
        .accessibilityLabel("Größe ändern")
    }
}

struct PanelResizeHandle: NSViewRepresentable {
    let edge: ResizeEdge
    let apply: (Preferences, Double, Double) -> Void
    let start: (NSRect?) -> Preferences
    let end: () -> Void
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.edge = edge; view.apply = apply; view.start = start; view.end = end
    }
    final class HandleView: NSView {
        var edge = ResizeEdge.bottom
        var apply: ((Preferences, Double, Double) -> Void)?
        var start: ((NSRect?) -> Preferences)?
        var end: (() -> Void)?
        /// The global pointer position. The panel moves while it resizes, so
        /// window-relative event locations would drift; tests inject a source.
        var locate: (NSEvent) -> NSPoint = { _ in NSEvent.mouseLocation }
        private var origin: (mouse: NSPoint, prefs: Preferences)?
        // Otherwise a floating panel (movable by background) moves instead of resizing.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        var cursor: NSCursor {
            switch edge {
            case .left, .right: .resizeLeftRight
            case .bottom: .resizeUpDown
            case .bottomLeft: .frameResize(position: .bottomLeft, directions: .all)
            case .bottomRight: .frameResize(position: .bottomRight, directions: .all)
            }
        }

        // The prompter panel never becomes key, so cursor rects stay inactive.
        // A tracking area that is always active sets the cursor instead.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { cursor.set() }
        override func mouseExited(with event: NSEvent) { if origin == nil { NSCursor.arrow.set() } }

        override func mouseDown(with event: NSEvent) {
            guard let prefs = start?(window?.frame) else { return }
            origin = (locate(event), prefs)
            cursor.set()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let origin else { return }
            let now = locate(event)
            apply?(origin.prefs, now.x - origin.mouse.x, now.y - origin.mouse.y)
            cursor.set()
        }
        override func mouseUp(with event: NSEvent) {
            guard origin != nil else { return }
            origin = nil
            end?()
            if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
        }
    }
}
