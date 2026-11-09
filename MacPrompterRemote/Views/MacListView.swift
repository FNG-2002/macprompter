import SwiftUI

struct MacListView: View {
    let client: RemoteClient
    @State private var pairingTarget: RemoteClient.DiscoveredMac?

    private var missingPairings: [PairedMac] {
        client.paired.filter { pairing in !client.discovered.contains { $0.serverID == pairing.serverID } }
    }

    var body: some View {
        List {
            if case .failed(let message) = client.phase {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Ausblenden") { client.dismissFailure() }
                }
            }
            if !client.discovered.isEmpty {
                Section {
                    ForEach(client.discovered) { mac in
                        Button { select(mac) } label: { MacRow(client: client, mac: mac) }
                            .swipeActions {
                                if let pairing = client.pairing(for: mac) {
                                    Button("Kopplung entfernen", role: .destructive) { client.forget(pairing.serverID) }
                                }
                            }
                    }
                } header: {
                    Text("Macs in der Nähe")
                } footer: {
                    Text("Neuen Mac koppeln: Am Mac unter Einstellungen → iPhone-Fernbedienung „iPhone koppeln …“ wählen.")
                }
            }
            if !missingPairings.isEmpty {
                Section("Gekoppelt, gerade nicht erreichbar") {
                    ForEach(missingPairings) { pairing in
                        Label(pairing.name, systemImage: "macbook").foregroundStyle(.secondary)
                            .swipeActions {
                                Button("Kopplung entfernen", role: .destructive) { client.forget(pairing.serverID) }
                            }
                    }
                }
            }
        }
        .overlay { if client.discovered.isEmpty { emptyState } }
        .navigationTitle("macprompter Remote")
        .sheet(item: $pairingTarget) { mac in PairingSheet(client: client, macID: mac.id) }
    }

    private func select(_ mac: RemoteClient.DiscoveredMac) {
        if client.pairing(for: mac) != nil { client.connect(mac) } else { pairingTarget = mac }
    }

    @ViewBuilder private var emptyState: some View {
        switch client.browserState {
        case .denied:
            ContentUnavailableView {
                Label("Lokales Netzwerk nicht erlaubt", systemImage: "wifi.exclamationmark")
            } description: {
                Text("macprompter Remote braucht Zugriff auf das lokale Netzwerk, um deinen Mac zu finden.")
            } actions: {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(.glassProminent)
            }
        case .failed(let message):
            ContentUnavailableView("Suche nicht möglich", systemImage: "exclamationmark.triangle", description: Text(message))
        default:
            ContentUnavailableView {
                Label("Suche nach deinem Mac …", systemImage: "macbook.and.iphone")
            } description: {
                Text("Schalte am Mac unter Einstellungen → iPhone-Fernbedienung die Fernsteuerung ein. WLAN muss auf beiden Geräten eingeschaltet sein, ein gemeinsames WLAN-Netz ist aber nicht nötig.")
            } actions: {
                ProgressView()
            }
        }
    }
}

private struct MacRow: View {
    let client: RemoteClient
    let mac: RemoteClient.DiscoveredMac

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "macbook")
                .font(.title2).foregroundStyle(.tint).symbolRenderingMode(.hierarchical)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy { ProgressView() } else {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(client.pairing(for: mac) != nil ? "Verbindet mit diesem Mac." : "Öffnet die Kopplung.")
    }

    private var subtitle: String {
        if client.pairing(for: mac) != nil { return "Gekoppelt · Tippen zum Verbinden" }
        return mac.pairingSalt != nil ? "Bereit zum Koppeln" : "Nicht gekoppelt"
    }

    private var isBusy: Bool {
        switch client.phase {
        case .connecting(let name), .pairing(let name): name == mac.name
        default: false
        }
    }
}

private struct PairingSheet: View {
    let client: RemoteClient
    let macID: String
    @State private var code = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var mac: RemoteClient.DiscoveredMac? { client.discovered.first { $0.id == macID } }
    private var isPairing: Bool {
        switch client.phase { case .pairing, .connecting: true; default: false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "lock.laptopcomputer")
                        .font(.system(size: 54)).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Mit „\(mac?.name ?? "Mac")“ koppeln").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(mac?.pairingSalt != nil
                             ? "Gib den sechsstelligen Code ein, den dein Mac unter Einstellungen → iPhone-Fernbedienung anzeigt."
                             : "Wähle am Mac unter Einstellungen → iPhone-Fernbedienung „iPhone koppeln …“. Danach erscheint hier das Codefeld.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if mac?.pairingSalt != nil {
                        TextField("000000", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().kerning(8)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 18, style: .continuous))
                            .focused($focused)
                            .accessibilityLabel("Kopplungscode")
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(RemotePairing.codeLength))
                                if digits != value { code = digits }
                            }
                            .onAppear { focused = true }
                        Button {
                            guard let mac else { return }
                            Task { await client.pair(mac, code: code) }
                        } label: {
                            Group {
                                if isPairing { ProgressView() } else { Text("Koppeln") }
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(code.count != RemotePairing.codeLength || isPairing)
                    } else {
                        ProgressView().padding()
                    }
                    if case .failed(let message) = client.phase {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.callout).foregroundStyle(.red)
                    }
                    Label("Die Verbindung bleibt im lokalen Netz und ist verschlüsselt.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { client.dismissFailure() }
        .onChange(of: client.isConnected) { _, connected in if connected { dismiss() } }
        .onChange(of: client.phase) { _, phase in if case .failed = phase { code = "" } }
    }
}
