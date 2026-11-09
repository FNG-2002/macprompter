import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    var preferences: PreferenceStore
    var library: ScriptLibrary
    let session: PrompterSession
    let remote = RemoteServer()
    let mcp = MCPServer()
    let presenter = PresentationController()
    @ObservationIgnored var presentationFiles: PresentationFiles
    /// Result of the last PDF update, shown in the slide editor.
    var presentationChange: (scriptID: UUID, change: PresentationChange)?
    var isUpdatingPresentation = false
    var showTemplates = false
    @ObservationIgnored var openLibraryWindow: (() -> Void)?
    /// While the user drags a prompter edge, hover pause stays on and the
    /// panel follows synchronously.
    @ObservationIgnored private(set) var isResizingPrompter = false
    @ObservationIgnored var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var overlay: OverlayController?
    @ObservationIgnored private var hotkeys: GlobalShortcuts?
    @ObservationIgnored private var settingsWindow: NSWindowController?
    var shortcutWarning: String?
    /// Input Monitoring: macOS only delivers other apps' scroll events with it.
    private(set) var scrollAccessGranted = true
    @ObservationIgnored var listenAccess: () -> Bool = { CGPreflightListenEventAccess() }
    /// The test host must never open System Settings on the developer's Mac.
    @ObservationIgnored var requestListenAccess: () -> Void = AppModel.isTestHost ? {} : { _ = CGRequestListenEventAccess() }
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private init() {
        let store = PreferenceStore()
        preferences = store
        session = PrompterSession(preferences: store)
        let library = ScriptLibrary()
        self.library = library
        presentationFiles = PresentationFiles(folder: library.fileURL.deletingLastPathComponent().appending(path: "Presentations", directoryHint: .isDirectory))
        presenter.model = self
    }

    func setup() {
        guard overlay == nil else { return }
        FontRegistration.register()
        overlay = OverlayController(model: self)
        session.onVisibilityChange = { [weak self] visible in
            if visible { self?.overlay?.show() } else { self?.overlay?.hide() }
        }
        hotkeys = GlobalShortcuts { [weak self] action in
            guard let self else { return }
            switch action {
            case 1: self.toggle()
            case 2: self.session.hide()
            case 3: self.session.nudge(-80)
            case 4: self.session.nudge(80)
            default: break
            }
        }
        observeActivation()
        refreshScrollAccess()
        if hotkeys?.registeredCount != 4 { shortcutWarning = "Ein globales Tastenkürzel ist bereits belegt. Die Steuerung in der App bleibt verfügbar." }
        observePreferences()
        applySelectedSettings()
        observeSelection()
        setupRemoteControl()
        setupAgentAccess()
    }

    private func observePreferences() {
        let old = preferences.value
        withObservationTracking {
            _ = preferences.value
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let new = self.preferences.value
                if old.mode != new.mode { self.session.pause() }
                if old.scriptSettings != new.scriptSettings { self.library.setSettings(new.scriptSettings, for: self.library.selectedID) }
                if old.scrollWheelAnywhere != new.scrollWheelAnywhere { self.overlay?.updateScrollMonitor() }
                if old.remoteControlEnabled != new.remoteControlEnabled { self.remote.setEnabled(new.remoteControlEnabled) }
                if old.mcpEnabled != new.mcpEnabled || old.mcpPort != new.mcpPort { self.mcp.configure(enabled: new.mcpEnabled, port: new.mcpPort) }
                if old.width != new.width || old.height != new.height || old.docked != new.docked || old.displayID != new.displayID {
                    self.overlay?.reposition()
                }
                self.observePreferences()
            }
        }
    }

    /// Called on activation, e.g. after returning from System Settings.
    func refreshScrollAccess() {
        let granted = listenAccess()
        // A monitor created before the grant can stay deaf; recreate it.
        if granted, !scrollAccessGranted { overlay?.updateScrollMonitor(reinstall: true) }
        scrollAccessGranted = granted
    }

    func beginPrompterResize() {
        isResizingPrompter = true
        session.setHover(true)
    }

    func resizePrompter(from start: Preferences, edge: ResizeEdge, dx: Double, dy: Double) {
        preferences.value.resize(from: start, edge: edge, dx: dx, dy: dy)
        // Synchronously, so the next drag event already sees the new frame.
        overlay?.reposition()
    }

    func endPrompterResize() {
        isResizingPrompter = false
        overlay?.reposition()   // re-evaluates hover from the real mouse position
    }

    /// Prompter and presenter clocks always restart together.
    func resetTimers() {
        session.resetTimer()
        presenter.resetTimer()
    }

    func toggle() {
        if !session.gate.isVisible {
            guard let script = library.selected, !ScriptParser.words(in: script.body).isEmpty else { return }
            session.present(script)
        }
        session.togglePlayback()
    }

    func preview() {
        guard let script = library.selected, !script.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.present(script)
    }

    func updateScript(title: String? = nil, body: String? = nil, language: SpeechLanguage? = nil) {
        library.update(title: title, body: body, language: language)
        if session.gate.isVisible, let script = library.selected, script.id == session.script.id {
            session.pause(); session.present(script)
        }
    }

    func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.macprompterScript, .plainText, .utf8PlainText, .rtf, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if url.pathExtension.lowercased() == ScriptDocument.fileExtension {
                Task { @MainActor in self?.openScriptFiles([url]) }
                return
            }
            Task { @MainActor in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let content: String
                    if url.pathExtension.lowercased() == "rtf" {
                        content = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
                    } else { content = try String(contentsOf: url, encoding: .utf8) }
                    self?.library.add(title: url.deletingPathExtension().lastPathComponent, body: content)
                } catch { self?.library.errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)" }
            }
        }
    }

    func exportScript() {
        guard let script = library.selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = script.title + ".txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try script.body.write(to: url, atomically: true, encoding: .utf8) }
            catch { Task { @MainActor in self?.library.errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)" } }
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 610), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Einstellungen"
            window.toolbarStyle = .automatic
            window.minSize = NSSize(width: 700, height: 540)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: self))
            window.setFrameAutosaveName("macprompter.settings")
            window.center()
            settingsWindow = NSWindowController(window: window)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

enum FontRegistration {
    static func register() {
        if let url = Bundle.main.url(forResource: "OpenDyslexic-Regular", withExtension: "otf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
