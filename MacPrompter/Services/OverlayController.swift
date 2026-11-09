import AppKit
import SwiftUI

final class PrompterPanel: NSPanel {
    var onScrollWheel: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Anywhere on the panel, including header and footer, never via SwiftUI.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let onScrollWheel { onScrollWheel(event) } else { super.sendEvent(event) }
    }
}

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private(set) var panel: PrompterPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var currentInset: Double?
    private var screenObserver: NSObjectProtocol?
    private var positioning = false
    private var scrollTap: ScrollWheelTap?
    private(set) var isMonitoringScrollWheel = false

    init(model: AppModel) {
        self.model = model
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    isolated deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        scrollTap?.invalidate()
    }

    func show() {
        if panel == nil {
            let panel = PrompterPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "macprompter · Prompter"
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
            // Best effort for legacy capture. ScreenCaptureKit can ignore this.
            panel.sharingType = .none
            #if DEBUG
            // README screenshots and demo video only (docs/MEDIA.md); never in Release builds.
            if UserDefaults.standard.bool(forKey: "OverlayCapturable") { panel.sharingType = .readOnly }
            #endif
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.onScrollWheel = { [weak self] in self?.scroll($0) }
            self.panel = panel
        }
        reposition()
        panel?.orderFrontRegardless()
        updateScrollMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        updateScrollMonitor()
    }

    func scroll(_ event: NSEvent) {
        model.session.scrollWheel(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
    }

    /// Scroll events anywhere while the prompter is on screen, also over areas
    /// that do not scroll and over the presentation windows. Other apps keep
    /// receiving them. Requires Input Monitoring.
    func updateScrollMonitor(reinstall: Bool = false) {
        let wanted = panel?.isVisible == true && model.preferences.value.scrollWheelAnywhere
        if reinstall || !wanted { scrollTap?.invalidate(); scrollTap = nil }
        isMonitoringScrollWheel = wanted
        guard wanted, scrollTap == nil else { return }
        // Without access the tap stays deaf; the system asks only once.
        guard model.listenAccess() else { model.requestListenAccess(); return }
        // The test host has no access and must never trigger the system prompt.
        guard !AppModel.isTestHost else { return }
        scrollTap = ScrollWheelTap { [weak self] event in
            guard Self.tapHandlesScroll(over: Self.windowUnderPointer()) else { return }
            self?.scroll(event)
        }
    }

    /// Over the prompter the panel itself scrolls; library, editor and
    /// settings keep their own scrolling. Presentation windows do not scroll.
    static func tapHandlesScroll(over window: NSWindow?) -> Bool {
        guard let window else { return true }
        return window is PresentationWindow
    }

    private static func windowUnderPointer() -> NSWindow? {
        NSApp.window(withWindowNumber: NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0))
    }

    func reposition() {
        guard let panel else { return }
        let prefs = model.preferences.value
        guard let screen = Self.screen(for: prefs) else { return }
        let width = min(prefs.width, screen.visibleFrame.width)
        let inset = prefs.docked ? max(8, screen.safeAreaInsets.top) : 4
        let height = min(prefs.height + inset, screen.visibleFrame.height)
        let area = screen.frame
        var origin = CGPoint(x: area.midX - width / 2, y: area.maxY - height)
        if !prefs.docked {
            let visible = screen.visibleFrame
            origin = CGPoint(x: prefs.floatingX ?? (visible.midX - width / 2), y: prefs.floatingY ?? (visible.maxY - height - 24))
            // Keep the entire panel reachable after a display is unplugged.
            origin.x = min(max(visible.minX, origin.x), visible.maxX - width)
            origin.y = min(max(visible.minY, origin.y), visible.maxY - height)
        }
        positioning = true
        panel.level = prefs.docked ? .init(rawValue: NSWindow.Level.mainMenu.rawValue + 1) : .floating
        panel.isMovableByWindowBackground = !prefs.docked
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        if let hostingView {
            if currentInset != inset { hostingView.rootView = OverlayView(model: model, topInset: inset) }
        } else {
            let view = NSHostingView(rootView: OverlayView(model: model, topInset: inset))
            hostingView = view
            panel.contentView = view
        }
        currentInset = inset
        positioning = false
        if !model.isResizingPrompter { model.session.setHover(panel.frame.contains(NSEvent.mouseLocation)) }
    }

    static func screen(for prefs: Preferences) -> NSScreen? {
        NSScreen.screens.first(where: { $0.displayID == prefs.displayID })
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// Height of the prompter below the menu bar, so other windows on the
    /// same screen can keep their content uncovered.
    static func coveredHeight(on screen: NSScreen, prefs: Preferences) -> Double {
        guard prefs.docked, screen.displayID == Self.screen(for: prefs)?.displayID else { return 0 }
        let height = min(prefs.height + max(8, screen.safeAreaInsets.top), screen.visibleFrame.height)
        return max(0, height - (screen.frame.maxY - screen.visibleFrame.maxY))
    }

    func windowDidMove(_ notification: Notification) {
        guard !positioning, !model.preferences.value.docked, let panel else { return }
        model.preferences.value.floatingX = panel.frame.minX
        model.preferences.value.floatingY = panel.frame.minY
        if let screen = panel.screen { model.preferences.value.displayID = screen.displayID }
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
