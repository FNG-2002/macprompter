import SwiftUI

@main
struct MacPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    var body: some Scene {
        Window("macprompter", id: "library") {
            WorkspaceView(model: model)
                .frame(minWidth: 1060, minHeight: 680)
                .preferredColorScheme(.dark)
                .tint(Design.accent)
                .onAppear { model.setup() }
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neues Skript") { model.library.add() }.keyboardShortcut("n")
                Button("Neu aus Vorlage …") { model.showTemplates = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Öffnen / Importieren …") { model.importScript() }.keyboardShortcut("o")
                Button("PDF-Präsentation importieren …") { model.importPresentation() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Skript sichern …") { model.saveScriptFile() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.library.selected == nil)
                Button("Als Text exportieren …") { model.exportScript() }.disabled(model.library.selected == nil)
            }
            CommandMenu("Präsentation") {
                Button(model.isPresenting ? "Präsentation beenden" : "Präsentieren") {
                    model.isPresenting ? model.endPresentation() : model.startPresentation()
                }.keyboardShortcut(.return, modifiers: [.command]).disabled(!model.isPresenting && model.library.selected?.presentation == nil)
                Divider()
                Button("Nächste Folie") { model.stepSlide(1) }.disabled(model.slideStatus == nil)
                Button("Vorherige Folie") { model.stepSlide(-1) }.disabled(model.slideStatus == nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen …") { model.showSettings() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("macprompter auf GitHub") { NSWorkspace.shared.open(AppInfo.repository) }
                Button("Versionshinweise") { NSWorkspace.shared.open(AppInfo.releases) }
                Button("Nach Updates suchen …") { Task { await model.checkForUpdatesNow() } }
                Button("Problem melden …") { NSWorkspace.shared.open(AppInfo.newIssue) }
                Divider()
                Button("Lizenzen und Danksagungen") { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate() }
            }
        }
        MenuBarExtra("macprompter", systemImage: "text.viewfinder") {
            MenuContent(model: model)
        }
    }
}

enum AppInfo {
    // Opened in the browser only on request. The app itself only asks GitHub's
    // API for the latest version number (UpdateCheck, can be switched off).
    static let repository = URL(string: "https://github.com/FNG-2002/macprompter")!
    static let releases = repository.appending(path: "releases")
    static let newIssue = repository.appending(path: "issues/new/choose")

    static func versionLabel(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.session.stateLabel)
        Button("Skriptbibliothek öffnen") { openWindow(id: "library"); NSApp.activate() }
            .onAppear { model.openLibraryWindow = { openWindow(id: "library") } }
        Divider()
        Button(model.session.gate.isPlaying ? "Pausieren" : "Starten") { model.toggle() }
        Button("Prompter ausblenden") { model.session.hide() }
        if model.isPresenting { Button("Präsentation beenden") { model.endPresentation() } }
        Divider()
        Button("Einstellungen …") { model.showSettings() }
        Button("macprompter beenden") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sleepObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.setup()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.session.hide() }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.openScriptFiles(urls)
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.session.hide()
        AppModel.shared.library.save()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
