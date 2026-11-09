import SwiftUI

/// Settings → iPhone-Fernbedienung. Off by default; the listener exists only while enabled.
struct RemoteSettingsSections: View {
    let remote: RemoteServer
    @Binding var isEnabled: Bool
    @State private var revokeCandidate: RemoteServer.Device?

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Fernsteuerung mit macprompter Remote")
                    Text("Start, Pause, Tempo, Scrollen und Folien vom iPhone aus – nur im lokalen Netz oder direkt per WLAN-Verbindung zwischen den Geräten.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
                .accessibilityHint("Macht diesen Mac für gekoppelte iPhones im lokalen Netz erreichbar.")
            if isEnabled {
                LabeledContent("Status") {
                    Label(statusText, systemImage: remote.isAdvertising ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                        .foregroundStyle(remote.isAdvertising ? Color.secondary : Color.orange)
                }
            }
            if let error = remote.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        if isEnabled {
            pairingSection
            devicesSection
        }
        Section("Sicherheit und Daten") {
            Label("Kein Internet, keine Cloud, kein Konto", systemImage: "lock.shield")
            Text("Die Verbindung ist mit TLS und einem Schlüssel pro Gerät verschlüsselt. Das iPhone erhält nur Skripttitel, Status, Fortschritt, Tempo und Foliennummer – keine Skripttexte, kein Audio, keine Transkripte.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Der sechsstellige Code schützt nur die kurze Kopplung. Koppel möglichst nicht in fremden oder öffentlichen Netzen und entferne Geräte, die du nicht mehr nutzt.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        guard remote.isAdvertising else { return remote.errorMessage == nil ? "Wird gestartet …" : "Nicht erreichbar" }
        return "Sichtbar als „\(remote.macName)“"
    }

    @ViewBuilder private var pairingSection: some View {
        Section("Neues iPhone koppeln") {
            if let pairing = remote.pairing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .center, spacing: 18) {
                        Text(pairing.code.prefix(3) + " " + pairing.code.suffix(3))
                            .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                            .textSelection(.disabled)
                            .accessibilityLabel("Kopplungscode \(pairing.code.map(String.init).joined(separator: " "))")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gültig noch \(remaining(until: pairing.expiresAt, now: context.date))")
                            Text(pairing.remainingAttempts == 1 ? "1 Versuch übrig" : "\(pairing.remainingAttempts) Versuche übrig")
                                .foregroundStyle(.secondary)
                        }.font(.callout).monospacedDigit()
                        Spacer()
                        Button("Abbrechen") { remote.cancelPairing() }
                    }
                }
                Text("Öffne macprompter Remote auf dem iPhone, wähle diesen Mac und gib den Code ein.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Erzeugt einen einmaligen Code, der zwei Minuten gültig ist.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("iPhone koppeln …") { remote.beginPairing() }.disabled(!remote.isAdvertising)
                }
                if let notice = remote.pairingNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var devicesSection: some View {
        Section("Gekoppelte Geräte") {
            if remote.devices.isEmpty {
                Text("Noch keine Geräte gekoppelt.").foregroundStyle(.secondary)
            }
            ForEach(remote.devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: "iphone").font(.title3).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(detail(for: device)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if remote.connectedDeviceIDs.contains(device.id) {
                        Label("Verbunden", systemImage: "circle.fill").labelStyle(.titleAndIcon)
                            .font(.caption).foregroundStyle(.green)
                    }
                    Button("Entfernen …") { revokeCandidate = device }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .confirmationDialog("Gerät entfernen?", isPresented: Binding(get: { revokeCandidate != nil }, set: { if !$0 { revokeCandidate = nil } }),
                            presenting: revokeCandidate) { device in
            Button("„\(device.name)“ entfernen", role: .destructive) { remote.revoke(device.id) }
        } message: { _ in
            Text("Das Gerät wird sofort getrennt und muss für eine erneute Nutzung neu gekoppelt werden.")
        }
    }

    private func detail(for device: RemoteServer.Device) -> String {
        let paired = "Gekoppelt am \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))"
        guard let seen = device.lastSeen else { return paired }
        return paired + " · zuletzt \(seen.formatted(.relative(presentation: .named)))"
    }

    private func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
