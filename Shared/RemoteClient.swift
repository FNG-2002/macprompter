import Foundation
import Network
import Observation
import CryptoKit

struct PairedMac: Codable, Equatable, Identifiable, Sendable {
    var serverID: UUID
    var name: String
    var deviceID: UUID
    var key: Data
    var id: UUID { serverID }
}

@MainActor protocol PairedMacStoring: AnyObject {
    func load() -> [PairedMac]
    func save(_ macs: [PairedMac])
}

/// iPhone side of the link. Platform-neutral so the Mac test suite can drive
/// it against the real `RemoteServer` over loopback.
@MainActor @Observable
final class RemoteClient {
    struct DiscoveredMac: Identifiable, Equatable {
        var name: String
        var endpoint: NWEndpoint
        var serverID: UUID?
        /// Present only while the Mac shows a pairing code.
        var pairingSalt: Data?
        var id: String { serverID?.uuidString ?? name }
    }
    enum Phase: Equatable {
        case idle
        case connecting(String)
        case pairing(String)
        case connected(String)
        case failed(String)
    }
    enum BrowserState: Equatable { case idle, searching, denied, failed(String) }

    private(set) var discovered: [DiscoveredMac] = []
    private(set) var browserState = BrowserState.idle
    private(set) var phase = Phase.idle
    private(set) var status: RemoteStatus?
    private(set) var scripts: [RemoteScriptSummary] = []
    private(set) var paired: [PairedMac]
    private(set) var connectedServerID: UUID?
    @ObservationIgnored var deviceName = "iPhone"
    @ObservationIgnored var retryDelay = Duration.milliseconds(700)
    @ObservationIgnored private let store: any PairedMacStoring
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var channel: RemoteChannel?
    @ObservationIgnored private var autoConnect = true
    /// Macs that refused our key this session; never retried automatically.
    @ObservationIgnored private var refused: Set<UUID> = []
    @ObservationIgnored private var attempt = 0

    init(store: any PairedMacStoring) {
        self.store = store
        paired = store.load()
    }

    func pairing(for mac: DiscoveredMac) -> PairedMac? {
        mac.serverID.flatMap { id in paired.first { $0.serverID == id } }
    }

    var isConnected: Bool { if case .connected = phase { true } else { false } }

    // MARK: Discovery

    func startBrowsing() {
        autoConnect = true
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: RemoteProtocol.serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserChanged(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(Array(results)) }
        }
        self.browser = browser
        browserState = .searching
        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel(); browser = nil
        discovered = []; browserState = .idle
    }

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .ready: browserState = .searching
        case .failed(let error), .waiting(let error):
            if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) { browserState = .denied }
            else { browserState = .failed(error.localizedDescription) }
            if case .failed = state { browser?.cancel(); browser = nil }
        default: break
        }
    }

    private func update(_ results: [NWBrowser.Result]) {
        discovered = results.compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            var mac = DiscoveredMac(name: name, endpoint: result.endpoint)
            if case .bonjour(let txt) = result.metadata {
                mac.serverID = txt["id"].flatMap(UUID.init(uuidString:))
                if txt["pair"] == "1" { mac.pairingSalt = txt["salt"].flatMap { Data(base64Encoded: $0) } }
            }
            return mac
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        connectAutomatically()
    }

    /// Discovery TXT data for loopback tests and manual endpoints.
    func add(_ mac: DiscoveredMac) {
        discovered.removeAll { $0.id == mac.id }
        discovered.append(mac)
    }

    private func connectAutomatically() {
        guard autoConnect, channel == nil else { return }
        if case .pairing = phase { return }
        // Most recently used first: `paired` keeps that order.
        for pairing in paired where !refused.contains(pairing.serverID) {
            if let mac = discovered.first(where: { $0.serverID == pairing.serverID }) { return connect(mac) }
        }
    }

    private var isFailedPhase: Bool { if case .failed = phase { true } else { false } }

    // MARK: Session

    func connect(_ mac: DiscoveredMac, retries: Int = 0) {
        guard let pairing = pairing(for: mac) else { return }
        refused.remove(pairing.serverID)
        attempt += 1
        let current = attempt
        phase = .connecting(mac.name)
        open(mac.endpoint, identity: pairing.deviceID.uuidString, key: pairing.key, onMessage: { [weak self] message in
            self?.session(message, pairing: pairing)
        }, onClose: { [weak self] error, wasReady in
            guard let self, current == self.attempt else { return }
            self.connectedServerID = nil; self.status = nil
            if !wasReady, retries > 0 {
                return self.retry { $0.connect(mac, retries: retries - 1) }
            }
            if !wasReady, error?.isTLSFailure == true {
                self.refused.insert(pairing.serverID)
                self.phase = .failed("„\(mac.name)“ kennt dieses iPhone nicht mehr. Entferne die Kopplung und koppel neu.")
            } else {
                self.phase = .failed(wasReady ? "Verbindung zu „\(mac.name)“ getrennt." : "„\(mac.name)“ ist nicht erreichbar.")
            }
        })
    }

    private func session(_ message: RemoteMessage, pairing: PairedMac) {
        switch message {
        case .challenge(let nonce):
            channel?.send(.hello(version: RemoteProtocol.version, deviceID: pairing.deviceID,
                proof: RemotePairing.proof(key: pairing.key, nonce: nonce, label: RemoteProtocol.authLabel)))
        case .welcome(let macName, let serverID):
            guard serverID == pairing.serverID else { return fail("Unerwarteter Mac. Bitte neu koppeln.") }
            connectedServerID = serverID
            phase = .connected(macName)
            var updated = paired.filter { $0.serverID != serverID }
            var entry = pairing; entry.name = macName
            updated.insert(entry, at: 0)
            if updated != paired { paired = updated; store.save(updated) }
        case .status(let status): self.status = status
        case .scripts(let scripts): self.scripts = scripts
        case .rejected(let reason):
            refused.insert(pairing.serverID)
            fail(reason == .incompatibleVersion ? "Bitte macprompter auf dem Mac und dem iPhone aktualisieren."
                 : "Dieser Mac kennt dein iPhone nicht mehr. Entferne die Kopplung und koppel neu.")
        default: break
        }
    }

    func send(_ command: RemoteCommand) {
        guard isConnected else { return }
        channel?.send(.command(command))
    }

    func disconnect() {
        autoConnect = false
        attempt += 1
        channel?.close(); channel = nil
        connectedServerID = nil; status = nil; scripts = []
        phase = .idle
    }

    /// Ends the session when the app leaves the foreground; `startBrowsing` resumes.
    func suspend() {
        disconnect()
        stopBrowsing()
    }

    func forget(_ serverID: UUID) {
        if connectedServerID == serverID { disconnect() }
        paired.removeAll { $0.serverID == serverID }
        store.save(paired)
        refused.remove(serverID)
    }

    func dismissFailure() { if isFailedPhase { phase = .idle } }

    // MARK: Pairing

    func pair(_ mac: DiscoveredMac, code: String) async {
        guard RemotePairing.isValidCode(code) else { return fail("Bitte gib den sechsstelligen Code vom Mac ein.") }
        guard let salt = mac.pairingSalt else { return fail("Starte die Kopplung auf dem Mac unter Einstellungen → iPhone-Fernbedienung.") }
        channel?.close(); channel = nil
        attempt += 1
        let current = attempt
        phase = .pairing(mac.name)
        let key = await Task.detached(priority: .userInitiated) { RemotePairing.pairingKey(code: code, salt: salt) }.value
        guard current == attempt else { return }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        var finished = false
        open(mac.endpoint, identity: RemoteProtocol.pairingIdentity, key: key, onMessage: { [weak self] message in
            guard let self else { return }
            switch message {
            case .challenge(let nonce):
                self.channel?.send(.pairRequest(version: RemoteProtocol.version, deviceName: self.deviceName,
                    publicKey: privateKey.publicKey.rawRepresentation,
                    proof: RemotePairing.proof(key: key, nonce: nonce, label: RemoteProtocol.pairLabel)))
            case .paired(let deviceID, let serverID, let macName, let macPublic):
                guard let deviceKey = try? RemotePairing.deviceKey(privateKey: privateKey, peerPublicKey: macPublic, pairingKey: key,
                        deviceID: deviceID, macPublicKey: macPublic, phonePublicKey: privateKey.publicKey.rawRepresentation) else {
                    return self.fail("Kopplung fehlgeschlagen.")
                }
                finished = true
                let entry = PairedMac(serverID: serverID, name: macName, deviceID: deviceID, key: deviceKey)
                self.paired = [entry] + self.paired.filter { $0.serverID != serverID }
                self.store.save(self.paired)
                self.attempt += 1
                self.channel?.close(); self.channel = nil
                var target = mac; target.serverID = serverID; target.pairingSalt = nil
                self.add(target)
                // The Mac restarts its listener with the new key; retry briefly.
                self.retry { $0.connect(target, retries: 4) }
            case .rejected:
                self.fail("Die Kopplung wurde abgelehnt. Erzeuge auf dem Mac einen neuen Code.")
            default: break
            }
        }, onClose: { [weak self] error, wasReady in
            guard let self, !finished, current == self.attempt else { return }
            if case .failed = self.phase { return }
            self.phase = .failed(!wasReady && error?.isTLSFailure == true
                ? "Der Code stimmt nicht oder ist abgelaufen."
                : "„\(mac.name)“ ist nicht erreichbar.")
        })
    }

    // MARK: Plumbing

    private func open(_ endpoint: NWEndpoint, identity: String, key: Data,
                      onMessage: @escaping (RemoteMessage) -> Void,
                      onClose: @escaping (NWError?, Bool) -> Void) {
        channel?.close()
        let channel = RemoteChannel(NWConnection(to: endpoint, using: RemoteTransport.parameters(keys: [(identity, key)])))
        channel.onMessage = onMessage
        channel.onClose = { [weak self, weak channel] error, wasReady in
            if let self, self.channel === channel { self.channel = nil }
            onClose(error, wasReady)
        }
        self.channel = channel
        channel.start()
    }

    private func retry(_ action: @escaping (RemoteClient) -> Void) {
        let current = attempt
        Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard let self, current == self.attempt else { return }
            action(self)
        }
    }

    private func fail(_ message: String) {
        attempt += 1
        channel?.close(); channel = nil
        connectedServerID = nil; status = nil
        phase = .failed(message)
    }
}
