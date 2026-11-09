import AppKit
import SwiftUI
import QuartzCore

extension ReadingFont {
    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .system: return .systemFont(ofSize: size, weight: .medium)
        case .rounded: return Self.designed(.rounded, size: size)
        case .serif: return Self.designed(.serif, size: size)
        case .mono: return Self.designed(.monospaced, size: size)
        case .openDyslexic: return NSFont(name: "OpenDyslexic-Regular", size: size) ?? .systemFont(ofSize: size)
        }
    }

    private static func designed(_ design: NSFontDescriptor.SystemDesign, size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}

extension ReadingColor {
    var nsColor: NSColor { NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1) }
    var color: Color { Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

enum ScriptStyle {
    /// Voice mode: brightness of text that was already spoken.
    static let spokenAlpha = 0.38
    /// Voice mode: the current word as a highlighter mark, dark text on the
    /// app's accent, readable with every text colour.
    static let currentWordBackground = NSColor(srgbRed: 0.72, green: 0.67, blue: 1, alpha: 1)
    static let currentWordText = NSColor(white: 0.05, alpha: 1)

    static func attributed(_ text: String, font: NSFont, spacing: Double, color: NSColor = .white) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.paragraphSpacing = spacing * 0.5
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        for range in ScriptParser.cueRanges(in: text) {
            result.addAttributes([.foregroundColor: NSColor(white: 0.55, alpha: 1), .font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)], range: range)
        }
        return result
    }

    /// The side-pane preview at `scale`; in voice mode it shows the first
    /// words as spoken and the next one as the current word.
    static func preview(_ text: String, preferences p: Preferences, scale: Double) -> NSAttributedString {
        let color = p.textColor.nsColor
        let result = NSMutableAttributedString(attributedString: attributed(text, font: p.font.nsFont(size: p.fontSize * scale), spacing: p.lineSpacing * scale, color: color))
        let words = ScriptParser.words(in: text)
        if p.mode == .voice, words.count > 8 {
            let current = words[5].range
            result.addAttribute(.foregroundColor, value: color.withAlphaComponent(spokenAlpha), range: NSRange(location: 0, length: current.location))
            result.addAttributes([.backgroundColor: currentWordBackground, .foregroundColor: currentWordText], range: current)
        }
        return result
    }
}

struct ReaderView: View {
    var session: PrompterSession
    var preferences: Preferences
    var body: some View {
        // Establish observation in a SwiftUI body, not inside AppKit callbacks.
        // Pixel offsets intentionally bypass this bridge; semantic changes do not.
        ReaderBridge(session: session, preferences: preferences,
            scriptBody: session.script.body, activeWord: session.activeWordRange,
            target: session.targetCharacter, jump: session.jumpCharacter,
            running: session.gate.isVisible && session.gate.isPlaying
                && !session.gate.isHovering && !session.isPreparing)
    }
}

private struct ReaderBridge: NSViewRepresentable {
    var session: PrompterSession
    var preferences: Preferences
    let scriptBody: String
    let activeWord: NSRange?
    let target: Int?
    let jump: Int?
    let running: Bool
    func makeNSView(context: Context) -> ReaderViewport { ReaderViewport(session: session) }
    func updateNSView(_ view: ReaderViewport, context: Context) { view.update(preferences: preferences) }
}

final class ReaderViewport: NSView {
    private let clip = NSClipView()
    private let text = NSTextView()
    private let session: PrompterSession
    private var lastBody = ""
    private var lastPreferences: Preferences?
    private var lastSize = NSSize.zero
    private var contentHeight = 0.0
    private var layoutRevision: UInt64 = 0
    private var pendingGeometry: Int?
    private var frameLink: CADisplayLink?
    private let frameTarget = ReaderFrameTarget()
    private var previousFrame: CFTimeInterval?
    private(set) var textLayoutCount = 0
    var isFrameClockRunning: Bool { frameLink.map { !$0.isPaused } ?? false }
    private var laidOut = false
    private var highlightedRange: NSRange?
    /// Voice mode: text before the spoken word is dimmed up to here.
    private var dimmedLength = 0
    override var isFlipped: Bool { true }

    init(session: PrompterSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        clip.drawsBackground = false
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        clip.documentView = text
        addSubview(clip)
        session.onOffsetChange = { [weak self] in self?.scrollToOffset() }
        frameTarget.reader = self
        session.onManualMovement = { [weak self] in self?.followManualMovement() }
        session.voiceGeometry = { [weak self] character in self?.continuousVoiceOffset(at: character) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Promptertext")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameLink?.invalidate(); frameLink = nil; previousFrame = nil
        if window != nil {
            let link = displayLink(target: frameTarget, selector: #selector(ReaderFrameTarget.frame(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            frameLink = link
            synchronizeFrameClock()
        }
    }

    isolated deinit { frameLink?.invalidate() }

    private func synchronizeFrameClock() {
        let running = window != nil && session.gate.isVisible && session.gate.isPlaying
            && !session.gate.isHovering && !session.isPreparing
        if frameLink?.isPaused == running { previousFrame = nil }
        frameLink?.isPaused = !running
    }

    fileprivate func displayFrame(_ link: CADisplayLink) {
        synchronizeFrameClock()
        guard !link.isPaused else { return }
        let timestamp = link.targetTimestamp
        let dt = previousFrame.map { timestamp - $0 } ?? (timestamp - link.timestamp)
        previousFrame = timestamp
        session.advanceFrame(by: dt)
        // Position changes go directly to NSClipView, without a SwiftUI pass.
        scrollToOffset()
        synchronizeFrameClock()
    }

    func update(preferences: Preferences) {
        let typographyChanged = lastPreferences?.font != preferences.font || lastPreferences?.fontSize != preferences.fontSize || lastPreferences?.lineSpacing != preferences.lineSpacing || lastPreferences?.mode != preferences.mode
        if lastBody != session.script.body || typographyChanged || lastPreferences?.textColor != preferences.textColor {
            // A colour change keeps the layout; only glyph colours change.
            let relayout = lastBody != session.script.body || typographyChanged
            lastBody = session.script.body
            text.textStorage?.setAttributedString(ScriptStyle.attributed(lastBody, font: preferences.font.nsFont(size: preferences.fontSize), spacing: preferences.lineSpacing, color: preferences.textColor.nsColor))
            setAccessibilityValue(lastBody)
            if let manager = text.layoutManager {
                let all = NSRange(location: 0, length: (lastBody as NSString).length)
                manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
                manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            }
            highlightedRange = nil
            dimmedLength = 0
            if relayout { laidOut = false; needsLayout = true }
        }
        lastPreferences = preferences
        updateWordHighlight()
        synchronizeFrameClock()
        if laidOut { applyPosition() }
    }

    override func layout() {
        super.layout()
        clip.frame = bounds
        let textChanged = !laidOut || lastSize.width != bounds.width
        let geometryChanged = textChanged || lastSize.height != bounds.height
        if textChanged {
            text.setFrameSize(NSSize(width: bounds.width, height: 100000))
            text.textContainer?.containerSize = NSSize(width: max(1, bounds.width - 24), height: .greatestFiniteMagnitude)
            if let container = text.textContainer, let manager = text.layoutManager {
                manager.ensureLayout(for: container)
                contentHeight = manager.usedRect(for: container).height + 24
                textLayoutCount += 1
            }
            laidOut = true
        }
        if geometryChanged {
            lastSize = bounds.size
            text.setFrameSize(NSSize(width: bounds.width, height: contentHeight + bounds.height * 0.7))
            let maximum = max(0, contentHeight - bounds.height * 0.3)
            layoutRevision &+= 1
            let revision = layoutRevision
            pendingGeometry = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.layoutRevision == revision else { return }
                self.session.maximumOffset = maximum
                self.session.offset = min(self.session.offset, maximum)
                self.session.refreshVoiceLayout()
                self.applyPosition()
            }
        }
        applyPosition()
    }

    /// Voice mode: spoken text is dimmed, the current word is marked like a
    /// highlighter, and the text still to read keeps full brightness.
    private func updateWordHighlight() {
        let length = (lastBody as NSString).length
        let range = lastPreferences?.mode == .voice ? session.activeWordRange.flatMap { NSMaxRange($0) <= length ? $0 : nil } : nil
        defer { session.didApplyWordHighlight(highlightedRange) }
        guard highlightedRange != range, let manager = text.layoutManager else { return }
        // Temporary attributes never change glyph widths or text layout.
        if let old = highlightedRange {
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: old)
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: old)
        }
        let dimmed = min(range?.location ?? 0, length)
        if dimmed > dimmedLength {
            let color = (lastPreferences?.textColor ?? .white).nsColor.withAlphaComponent(ScriptStyle.spokenAlpha)
            manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: NSRange(location: dimmedLength, length: dimmed - dimmedLength))
        } else if dimmed < dimmedLength {
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: dimmed, length: min(dimmedLength, length) - dimmed))
        }
        dimmedLength = dimmed
        if let range {
            manager.addTemporaryAttributes([
                .foregroundColor: ScriptStyle.currentWordText,
                .backgroundColor: ScriptStyle.currentWordBackground
            ], forCharacterRange: range)
        }
        highlightedRange = range
    }


    private func applyPosition() {
        if let character = session.jumpCharacter, laidOut, !lastBody.isEmpty, let manager = text.layoutManager {
            let index = min(max(0, character), (lastBody as NSString).length - 1)
            let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: index), effectiveRange: nil)
            session.resolveJump(line.minY - 12, for: character)
        }
        if let character = session.targetCharacter, pendingGeometry != character, !session.gate.isHovering,
           lastPreferences?.mode == .voice,
           let manager = text.layoutManager, text.textContainer != nil, !lastBody.isEmpty {
            func line(at character: Int) -> CGRect {
                let index = min(max(0, character), max(0, (lastBody as NSString).length - 1))
                let glyph = manager.glyphIndexForCharacter(at: index)
                return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let nextLine = line(at: character)
            let currentLine = line(at: session.activeWordRange?.location ?? character)
            // Keep the spoken line near the focus band. Across a cue/blank-line
            // gap, reveal the next spoken line above the fade even in silence.
            let value = max(0, currentLine.minY - 12, nextLine.maxY + 12 - bounds.height * 0.58)
            pendingGeometry = character
            let revision = layoutRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.layoutRevision == revision else { return }
                self.pendingGeometry = nil
                self.session.resolveVoiceDestination(value, for: character)
            }
        }
        scrollToOffset()
    }

    /// Speech-paced scrolling: the spoken line rises from the second row to
    /// the top while it is read, instead of stepping once per line. The next
    /// spoken line stays revealed above the fade as in the stepped mode.
    func continuousVoiceOffset(at character: Double) -> Double? {
        guard laidOut, !lastBody.isEmpty, let manager = text.layoutManager else { return nil }
        let index = min(max(0, Int(character)), (lastBody as NSString).length - 1)
        let glyph = manager.glyphIndexForCharacter(at: index)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let used = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let x = line.minX + manager.location(forGlyphAt: glyph).x
        let fraction = used.width > 0 ? min(1, max(0, (x - used.minX) / used.width)) : 0
        return max(0, line.minY - 12 - line.height * (1 - fraction), line.maxY + 12 - bounds.height * 0.58)
    }

    private func scrollToOffset() {
        guard laidOut, clip.bounds.minY != session.offset else { return }
        clip.scroll(to: NSPoint(x: 0, y: session.offset))
        reportReadingPosition()
    }

    /// Slide sync from the line in the focus band: for timer scrolling, and in
    /// every mode after a manual move. Otherwise the spoken words lead.
    private func reportReadingPosition(manual: Bool = false) {
        guard session.slideTimeline != nil, manual || lastPreferences?.mode != .voice,
              let manager = text.layoutManager, let container = text.textContainer else { return }
        let point = CGPoint(x: 0, y: session.offset + 12 + (lastPreferences?.fontSize ?? 28) * 0.5)
        let glyph = manager.glyphIndex(for: point, in: container)
        if glyph < manager.numberOfGlyphs { session.readerReached(character: manager.characterIndexForGlyph(at: glyph), manual: manual) }
    }

    /// Scroll wheel, keys and iPhone. Callers already passed the gate; the
    /// scroll wheel also moves during hover.
    func followManualMovement() {
        guard session.gate.isVisible, let manager = text.layoutManager, let container = text.textContainer else { return }
        let glyph = manager.glyphIndex(for: CGPoint(x: 0, y: session.offset + 12), in: container)
        if glyph < manager.numberOfGlyphs { session.seekVoice(to: manager.characterIndexForGlyph(at: glyph)) }
        reportReadingPosition(manual: true)
    }
}

/// CADisplayLink retains its target. Keep the reader weak to avoid retaining
/// closed panels through the run loop.
@MainActor private final class ReaderFrameTarget: NSObject {
    weak var reader: ReaderViewport?
    @objc func frame(_ link: CADisplayLink) { reader?.displayFrame(link) }
}

struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = NSTextView()
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textContainerInset = NSSize(width: 24, height: 24)
        editor.font = .systemFont(ofSize: 18)
        editor.textColor = NSColor(white: 0.88, alpha: 1)
        editor.insertionPointColor = .white
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Skript bearbeiten")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
            context.coordinator.highlight(editor)
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        init(_ parent: ScriptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            if !editor.hasMarkedText() { highlight(editor) }
        }
        func highlight(_ editor: NSTextView) { ScriptEditor.style(editor) }
    }

    static func style(_ editor: NSTextView, size: CGFloat = 18) {
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = size * 4 / 9
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(white: 0.88, alpha: 1), .paragraphStyle: paragraph]
        editor.textStorage?.beginEditing()
        editor.textStorage?.setAttributes(base, range: range)
        for cue in ScriptParser.cueRanges(in: editor.string) {
            editor.textStorage?.addAttribute(.foregroundColor, value: NSColor(white: 0.5, alpha: 1), range: cue)
        }
        editor.textStorage?.endEditing()
        editor.typingAttributes = base
    }
}
