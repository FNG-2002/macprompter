import Foundation
import Network
import Observation
import CryptoKit

/// Remote-control endpoint for macprompter Remote. Opt-in: the listener only
/// exists while the user has enabled it. Paired device keys live in the app's
/// sandbox container (`remote-devices.json`), never in the script library.
@MainActor @Observable
final class RemoteServer {
    struct Device: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var key: Data
        var pairedAt: Date
        var lastSeen: Date?
    }
    private struct Stored: Codable {
        var serverID = UUID()
        var devices: [Device] = []
    }
    @MainActor private final class Peer {
        let channel: RemoteChannel
        let nonce = RemotePairing.randomBytes(32)
        var deviceID: UUID?
        init(_ channel: RemoteChannel) { self.channel = channel }
    }

    private(set) var isEnabled = false
    private(set) var isAdvertising = false
    private(set) var serviceName: String?
    private(set) var errorMessage: String?
    private(set) var devices: [Device] = []
    private(set) var connectedDeviceIDs: Set<UUID> = []
    private(set) var pairing: RemotePairingWindow?
    private(set) var pairingNotice: String?
    private(set) var serverID: UUID
    @ObservationIgnored var bridge: RemoteBridge?
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var pairingIterations = RemotePairing.iterations
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var listenerGeneration = 0
    @ObservationIgnored private var peers: [ObjectIdentifier: Peer] = [:]
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var lastStatus: RemoteStatus?
    @ObservationIgnored private var lastScripts: [RemoteScriptSummary]?
    @ObservationIgnored private(set) var port: UInt16?

    init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "macprompter", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "remote-devices.json")
        var stored = Stored()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
                stored = decoded
            } else {
                // Never overwrite an unreadable file; remote control just starts without devices.
                canSave = false
                errorMessage = "Die Geräteliste konnte nicht gelesen werden und bleibt unverändert: \(fileURL.path)"
            }
        }
        serverID = stored.serverID
        devices = stored.devices
    }

    var macName: String { serviceName ?? Host.current().localizedName ?? "Mac" }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { restartListener() } else { stop() }
    }

    // MARK: Pairing

    func beginPairing() {
        guard isEnabled else { return }
        pairing = RemotePairingWindow(now: now(), iterations: pairingIterations)
        pairingNotice = nil
        restartListener()
        let deadline = pairing!.expiresAt
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.pairing?.expiresAt == deadline else { return }
            self.endPairing(notice: "Der Kopplungscode ist abgelaufen.")
        }
    }

    func cancelPairing() { endPairing(notice: nil) }

    private func endPairing(notice: String?) {
        guard pairing != nil else { return }
        pairing = nil
        pairingNotice = notice
        pairingTask?.cancel(); pairingTask = nil
        // Open pairing links are not cut here: the answer to a successful
        // pairing may still be in flight, and any later request finds the window closed.
        if isEnabled { restartListener() }
    }

    private func registerPairingFailure() {
        guard var window = pairing else { return }
        if window.registerFailure(at: now()) { pairing = window }
        else { endPairing(notice: "Zu viele Fehlversuche. Erzeuge bei Bedarf einen neuen Code.") }
    }

    func revoke(_ id: UUID) {
        devices.removeAll { $0.id == id }
        save()
        for peer in peers.values where peer.deviceID == id { peer.channel.close() }
        if isEnabled { restartListener() }
    }

    // MARK: Listener

    private func stop() {
        listenerGeneration += 1
        listener?.cancel(); listener = nil
        for peer in peers.values { peer.channel.close() }
        peers = [:]; connectedDeviceIDs = []
        pairing = nil; pairingTask?.cancel(); pairingTask = nil
        statusTask?.cancel(); statusTask = nil
        isAdvertising = false; port = nil
    }

    /// TLS keys are fixed per listener, so key changes restart it. Accepted
    /// connections are independent of the listener and stay up.
    private func restartListener() {
        listenerGeneration += 1
        let generation = listenerGeneration
        guard let old = listener else { return startListener(generation) }
        listener = nil
        old.stateUpdateHandler = { [weak self] state in
            guard case .cancelled = state else { return }
            // Wait for the Bonjour deregistration to avoid a renamed "Mac (2)".
            MainActor.assumeIsolated { self?.startListener(generation) }
        }
        old.cancel()
    }

    private func startListener(_ generation: Int) {
        guard isEnabled, generation == listenerGeneration, listener == nil else { return }
        var keys = devices.map { (identity: $0.id.uuidString, key: $0.key) }
        var txt = ["v": "\(RemoteProtocol.version)", "id": serverID.uuidString]
        if let pairing, pairing.isOpen(at: now()) {
            keys.append((RemoteProtocol.pairingIdentity, pairing.key))
            txt["pair"] = "1"; txt["salt"] = pairing.salt.base64EncodedString()
        }
        do {
            let parameters = RemoteTransport.parameters(keys: keys, listener: true)
            parameters.allowLocalEndpointReuse = true
            // Keep the port across key changes so a client's resolved endpoint stays valid.
            let listener = try port.flatMap(NWEndpoint.Port.init(rawValue:)).map { try NWListener(using: parameters, on: $0) }
                ?? NWListener(using: parameters)
            listener.service = NWListener.Service(type: RemoteProtocol.serviceType, txtRecord: NWTXTRecord(txt))
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerState(state, listener: listener) }
            }
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                MainActor.assumeIsolated {
                    if case .add(.service(let name, _, _, _)) = change { self?.serviceName = name }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            errorMessage = "Die Fernsteuerung konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    private func listenerState(_ state: NWListener.State, listener: NWListener) {
        guard listener === self.listener else { return }
        switch state {
        case .ready:
            isAdvertising = true; port = listener.port?.rawValue
            if canSave { errorMessage = nil }
        case .failed(let error):
            self.listener = nil; listener.cancel()
            // The previous port may be taken by now; fall back to any port once.
            if port != nil { port = nil; return startListener(listenerGeneration) }
            isAdvertising = false
            errorMessage = "Die Fernsteuerung ist im lokalen Netz nicht erreichbar: \(error.localizedDescription)"
        case .waiting(let error):
            isAdvertising = false
            errorMessage = "Die Fernsteuerung ist im lokalen Netz nicht erreichbar: \(error.localizedDescription)"
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        // A remote needs one or two links; cap unauthenticated churn.
        guard peers.count < 8 else { return connection.cancel() }
        let channel = RemoteChannel(connection)
        let peer = Peer(channel)
        let key = ObjectIdentifier(peer)
        peers[key] = peer
        channel.onReady = { [weak self, weak peer] in
            guard let peer else { return }
            peer.channel.send(.challenge(nonce: peer.nonce))
            Task { [weak self, weak peer] in
                try? await Task.sleep(for: .seconds(10))
                guard let peer, peer.deviceID == nil, self?.peers[ObjectIdentifier(peer)] != nil else { return }
                peer.channel.close()
            }
        }
        channel.onMessage = { [weak self, weak peer] message in
            guard let self, let peer else { return }
            self.receive(message, from: peer)
        }
        channel.onClose = { [weak self] error, wasReady in
            guard let self, let peer = self.peers.removeValue(forKey: key) else { return }
            if !wasReady, error?.isTLSFailure == true { self.registerPairingFailure() }
            if let id = peer.deviceID, !self.peers.values.contains(where: { $0.deviceID == id }) {
                self.connectedDeviceIDs.remove(id)
            }
            self.updateStatusLoop()
        }
        channel.start()
    }

    // MARK: Messages

    private func receive(_ message: RemoteMessage, from peer: Peer) {
        switch message {
        case .hello(let version, let deviceID, let proof):
            guard peer.deviceID == nil else { return }
            guard version == RemoteProtocol.version else { return peer.channel.finish(with: .rejected(.incompatibleVersion)) }
            guard let index = devices.firstIndex(where: { $0.id == deviceID }),
                  RemotePairing.verify(proof, key: devices[index].key, nonce: peer.nonce, label: RemoteProtocol.authLabel) else {
                return peer.channel.finish(with: .rejected(.unknownDevice))
            }
            peer.deviceID = deviceID
            devices[index].lastSeen = now()
            save()
            connectedDeviceIDs.insert(deviceID)
            peer.channel.send(.welcome(macName: macName, serverID: serverID))
            if let bridge {
                peer.channel.send(.scripts(bridge.scripts()))
                peer.channel.send(.status(bridge.status()))
            }
            updateStatusLoop()
        case .pairRequest(let version, let deviceName, let publicKey, let proof):
            guard peer.deviceID == nil else { return }
            guard version == RemoteProtocol.version else { return peer.channel.finish(with: .rejected(.incompatibleVersion)) }
            guard let window = pairing, window.isOpen(at: now()) else { return peer.channel.finish(with: .rejected(.pairingClosed)) }
            guard RemotePairing.verify(proof, key: window.key, nonce: peer.nonce, label: RemoteProtocol.pairLabel) else {
                registerPairingFailure()
                return peer.channel.finish(with: .rejected(.pairingClosed))
            }
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let macPublic = privateKey.publicKey.rawRepresentation
            let deviceID = UUID()
            guard let key = try? RemotePairing.deviceKey(privateKey: privateKey, peerPublicKey: publicKey, pairingKey: window.key,
                    deviceID: deviceID, macPublicKey: macPublic, phonePublicKey: publicKey) else {
                return peer.channel.finish(with: .rejected(.pairingClosed))
            }
            let name = String(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            devices.append(Device(id: deviceID, name: name.isEmpty ? "iPhone" : name, key: key, pairedAt: now()))
            save()
            peer.channel.finish(with: .paired(deviceID: deviceID, serverID: serverID, macName: macName, publicKey: macPublic))
            endPairing(notice: "„\(devices.last!.name)“ wurde gekoppelt.")
        case .command(let command):
            guard peer.deviceID != nil, let bridge else { return }
            bridge.perform(command)
            pushStatus()
        default: break
        }
    }

    // MARK: Status

    /// Polls while a device is connected: scroll progress is deliberately not
    /// observable (display-link rate), so a 4 Hz snapshot is the cheap path.
    private func updateStatusLoop() {
        if connectedDeviceIDs.isEmpty {
            statusTask?.cancel(); statusTask = nil; lastStatus = nil; lastScripts = nil
        } else if statusTask == nil {
            statusTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.pushStatus()
                }
            }
        }
    }

    func pushStatus() {
        guard let bridge, !connectedDeviceIDs.isEmpty else { return }
        let scripts = bridge.scripts()
        if scripts != lastScripts { lastScripts = scripts; broadcast(.scripts(scripts)) }
        let status = bridge.status()
        if status != lastStatus { lastStatus = status; broadcast(.status(status)) }
    }

    private func broadcast(_ message: RemoteMessage) {
        for peer in peers.values where peer.deviceID != nil { peer.channel.send(message) }
    }

    private func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Stored(serverID: serverID, devices: devices)).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { errorMessage = "Geräteliste konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }
}
