import AppKit
import PDFKit
import SwiftUI
import Observation

final class PresentationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen slides for the audience and an optional presenter view on the
/// prompter's screen. The visible page is always `session.currentSlide`.
@MainActor @Observable
final class PresentationController: NSObject, NSWindowDelegate {
    private(set) var isPresenting = false
    var document: PDFDocument?
    private(set) var startedAt = Date()
    var blackout = false
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var closing = false
    @ObservationIgnored private var slideHotkeys: GlobalShortcuts?

    func page(_ index: Int?) -> PDFPage? {
        guard let index, let document, index >= 0, index < document.pageCount else { return nil }
        return document.page(at: index)
    }

    func start(document: PDFDocument) {
        if isPresenting { end() }
        self.document = document
        blackout = false; startedAt = Date()
        isPresenting = true
        buildWindows()
        slideHotkeys = GlobalShortcuts(keys: GlobalShortcuts.slideKeys) { [weak self] id in self?.step(id == 5 ? -1 : 1) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = PresentationKey(event)
            return MainActor.assumeIsolated { self?.handle(key) == true } ? nil : event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // A projector can disappear mid-talk; rebuild on the remaining screens.
            Task { @MainActor in guard let self, self.isPresenting else { return }; self.closeWindows(); self.buildWindows() }
        }
    }

    func end() {
        guard isPresenting else { return }
        isPresenting = false
        closeWindows()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        keyMonitor = nil; screenObserver = nil; slideHotkeys = nil
        document = nil
        model?.session.pause()
    }

    private func buildWindows() {
        guard let model else { return }
        let prefs = model.preferences.value
        let prompter = OverlayController.screen(for: prefs)
        let screens = NSScreen.screens
        guard let audience = screens.first(where: { prefs.presentationDisplayID != 0 && $0.displayID == prefs.presentationDisplayID })
            ?? screens.first(where: { $0.displayID != prompter?.displayID }) ?? prompter ?? NSScreen.main else { return }
        let slides = PresentationWindow(contentRect: audience.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        slides.title = "macprompter · Folien"
        slides.backgroundColor = .black
        slides.isReleasedWhenClosed = false
        slides.collectionBehavior = [.fullScreenAuxiliary]
        slides.contentView = NSHostingView(rootView: AudienceView(model: model))
        slides.setFrame(audience.frame, display: true)
        windows = [slides]
        var key: NSWindow = slides
        if prefs.presenterView, let prompter, prompter.displayID != audience.displayID {
            let presenter = PresentationWindow(contentRect: prompter.visibleFrame, styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            presenter.title = "Referentenansicht"
            presenter.titlebarAppearsTransparent = true
            presenter.isReleasedWhenClosed = false
            presenter.delegate = self
            presenter.contentView = NSHostingView(rootView: PresenterView(model: model,
                topReserve: OverlayController.coveredHeight(on: prompter, prefs: prefs)))
            presenter.setFrame(prompter.visibleFrame, display: true)
            windows.append(presenter)
            key = presenter
        }
        windows.forEach { $0.orderFrontRegardless() }
        NSApp.activate()
        key.makeKeyAndOrderFront(nil)
        // Dock and menu bar only exist on the main screen.
        NSApp.presentationOptions = audience.displayID == screens.first?.displayID ? [.hideDock, .hideMenuBar] : []
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func closeWindows() {
        closing = true
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = []
        closing = false
        NSApp.presentationOptions = []
    }

    func windowWillClose(_ notification: Notification) {
        if !closing { end() }
    }

    func resetTimer() { startedAt = Date() }

    func step(_ delta: Int) {
        blackout = false
        model?.stepSlide(delta)
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    /// Keys of keyboards and common presentation clickers.
    private func handle(_ key: PresentationKey) -> Bool {
        guard isPresenting, !key.hasModifiers, windows.contains(where: { $0.windowNumber == key.window }) else { return false }
        switch key.code {
        case 124, 125, 121, 49, 36, 76: step(1)    // → ↓ PageDown Space Return Enter
        case 123, 126, 116, 51: step(-1)           // ← ↑ PageUp Delete
        case 115: model?.showSlide(0)              // Home
        case 119: model?.showSlide((model?.slideStatus?.count ?? 1) - 1) // End
        case 53: end()                             // Esc
        default:
            guard key.characters == "b" || key.characters == "." else { return false }
            blackout.toggle()
        }
        return true
    }
}

struct PresentationKey: Sendable {
    let code: UInt16
    let characters: String
    let hasModifiers: Bool
    let window: Int
    init(_ event: NSEvent) {
        code = event.keyCode
        characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        hasModifiers = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        window = event.windowNumber
    }
}
