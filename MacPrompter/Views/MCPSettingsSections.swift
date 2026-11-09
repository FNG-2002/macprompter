import AppKit
import SwiftUI

/// Settings → KI-Agenten. MCP endpoint on 127.0.0.1, off by default.
struct MCPSettingsSections: View {
    let mcp: MCPServer
    @Binding var isEnabled: Bool
    @Binding var port: UInt16
    @State private var portText = ""
    @State private var showToken: Bool
    @State private var regenerateConfirmation = false
    @State private var copied: String?

    init(mcp: MCPServer, isEnabled: Binding<Bool>, port: Binding<UInt16>, revealToken: Bool = false) {
        self.mcp = mcp
        _isEnabled = isEnabled
        _port = port
        _showToken = State(initialValue: revealToken)
    }

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Zugriff für KI-Agenten (MCP)")
                    Text("Claude und andere MCP-fähige Agenten können Skripte und Präsentationen samt Text pro Folie anlegen und bearbeiten. Löschen ist nicht möglich.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
                .accessibilityHint("Startet einen lokalen MCP-Server, der nur auf diesem Mac erreichbar ist.")
            if isEnabled {
                LabeledContent("Status") {
                    let failed = !mcp.isRunning && mcp.errorMessage != nil
                    Label(mcp.isRunning ? "Bereit unter \(mcp.endpoint)" : (failed ? "Nicht erreichbar" : "Wird gestartet …"),
                          systemImage: mcp.isRunning ? "checkmark.circle" : (failed ? "exclamationmark.triangle" : "hourglass"))
                        .foregroundStyle(failed ? Color.orange : Color.secondary).textSelection(.enabled)
                }
            }
            if let error = mcp.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        Section("Verbindung") {
            LabeledContent("Port") {
                TextField("", text: $portText).labelsHidden().frame(width: 80).multilineTextAlignment(.trailing).monospacedDigit()
                    .onSubmit(commitPort)
                    .accessibilityLabel("Port")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Token")
                    Spacer()
                    Button { showToken.toggle() } label: { Image(systemName: showToken ? "eye.slash" : "eye") }
                        .help(showToken ? "Token verbergen" : "Token anzeigen")
                        .accessibilityLabel(showToken ? "Token verbergen" : "Token anzeigen")
                    Button { copy(mcp.token, as: "token") } label: { Image(systemName: copied == "token" ? "checkmark" : "doc.on.doc") }
                        .help("Token kopieren").accessibilityLabel("Token kopieren")
                    Button("Neu erzeugen …") { regenerateConfirmation = true }
                }
                // Full token, wrapped instead of truncated; selectable as a fallback to the copy button.
                Text(showToken ? mcp.token : String(repeating: "•", count: 24))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            Text("Der Token wirkt wie ein Passwort. Mit einem neuen Token müssen eingerichtete Agenten neu verbunden werden.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Einrichten") {
            snippet("Claude Code (Terminal)", claudeCode)
            snippet("Claude Desktop und Cowork (claude_desktop_config.json)", claudeDesktop)
            Text("In Claude Desktop unter Einstellungen → Entwickler → Konfiguration bearbeiten in „mcpServers“ eintragen und Claude neu starten. Das mitgelieferte Hilfsprogramm startet macprompter bei Bedarf; nach dem Verschieben der App die Konfiguration neu kopieren.")
                .font(.caption).foregroundStyle(.secondary)
            snippet("Konfiguration für andere MCP-Clients (JSON)", json)
            Text("macprompter muss laufen, solange ein Agent arbeitet.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Dateien von und für Agenten") {
            LabeledContent("Freigegebener Ordner") {
                HStack(spacing: 8) {
                    Text(mcp.folder?.path(percentEncoded: false) ?? "Keiner").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Wählen …", action: chooseFolder)
                    if mcp.folder != nil { Button("Entfernen") { mcp.setFolder(nil) } }
                }
            }
            Text("macprompter liest und schreibt nur in Ordnern, die du freigibst. Agenten erstellen hier aus PDFs Präsentationen, reichen neue Versionen nach und sichern oder laden macprompter-Dateien. Kleine Dateien können Agenten auch direkt mitschicken.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if isEnabled {
            Section("Letzte Zugriffe") {
                if mcp.recentCalls.isEmpty {
                    Text("Noch keine Zugriffe seit dem Start.").foregroundStyle(.secondary)
                }
                ForEach(mcp.recentCalls) { call in
                    LabeledContent {
                        Text(call.date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.secondary)
                    } label: {
                        Label(call.tool, systemImage: call.succeeded ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(call.succeeded ? Color.primary : Color.orange)
                    }
                }
            }
        }
        Section("Sicherheit") {
            Label("Nur auf diesem Mac erreichbar (127.0.0.1), kein Internet", systemImage: "lock.shield")
            Text("Jeder Aufruf braucht den Token. Agenten sehen die Texte deiner Skripte, sobald du sie verbindest; gib den Token nur Agenten, denen du das erlaubst. Protokolliert werden nur Werkzeugnamen und Uhrzeiten, keine Inhalte.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { portText = String(port) }
        .onChange(of: port) { _, value in portText = String(value) }
        .alert("Neuen Token erzeugen?", isPresented: $regenerateConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Neu erzeugen", role: .destructive) { mcp.regenerateToken() }
        } message: { Text("Bereits verbundene Agenten verlieren den Zugriff, bis du ihnen den neuen Token gibst.") }
    }

    private var claudeCode: String {
        "claude mcp add --transport http macprompter \(mcp.endpoint) --header \"Authorization: Bearer \(mcp.token)\""
    }

    private var claudeDesktop: String {
        MCPSettingsSections.claudeDesktopConfiguration(helper: Bundle.main.bundleURL.appending(path: MCPBridge.helperPath), token: mcp.token, port: mcp.port)
    }

    /// Claude Desktop starts only local programs; the helper forwards stdio to the HTTP endpoint.
    static func claudeDesktopConfiguration(helper: URL, token: String, port: UInt16) -> String {
        let server: JSONValue = ["command": .string(helper.path(percentEncoded: false)),
                                 "env": [MCPBridge.tokenVariable: .string(token), MCPBridge.portVariable: .string(String(port))]]
        return JSONValue.object(["mcpServers": ["macprompter": server]]).text
    }

    private var json: String {
        """
        {"mcpServers": {"macprompter": {"type": "http", "url": "\(mcp.endpoint)", "headers": {"Authorization": "Bearer \(mcp.token)"}}}}
        """
    }

    private func snippet(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Button { copy(value, as: title) } label: {
                    Label(copied == title ? "Kopiert" : "Kopieren", systemImage: copied == title ? "checkmark" : "doc.on.doc")
                }
            }
            Text(showToken ? value : value.replacingOccurrences(of: mcp.token, with: "•••"))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ value: String, as key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = key
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copied == key { copied = nil }
        }
    }

    private func commitPort() {
        if let value = UInt16(portText), value >= 1024 { port = value } else { portText = String(port) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Freigeben"
        panel.message = "Ordner, in dem Agenten PDFs und macprompter-Dateien lesen und sichern dürfen"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in mcp.setFolder(url) }
        }
    }
}
