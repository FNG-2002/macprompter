import Foundation
import Network

enum RemoteTransport {
    /// TLS with external pre-shared keys. Network.framework negotiates PSK only
    /// as TLS 1.2 `TLS_PSK_WITH_AES_128_GCM_SHA256` (measured; see docs/REMOTE.md).
    static func parameters(keys: [(identity: String, key: Data)], listener: Bool = false) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        for entry in keys {
            sec_protocol_options_add_pre_shared_key(options, dispatchData(entry.key), dispatchData(Data(entry.identity.utf8)))
        }
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let parameters = NWParameters(tls: tls, tcp: tcp)
        // Peer-to-peer (AWDL) lets the iPhone reach the Mac without shared Wi-Fi.
        parameters.includePeerToPeer = true
        if listener { parameters.acceptLocalOnly = true }
        return parameters
    }

    private static func dispatchData(_ data: Data) -> __DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    }
}

/// One framed connection. All callbacks arrive on the main queue.
@MainActor
final class RemoteChannel {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((RemoteMessage) -> Void)?
    /// Called once. `wasReady` is false when the TLS handshake never completed.
    var onClose: ((_ error: NWError?, _ wasReady: Bool) -> Void)?
    private var decoder = RemoteFrameDecoder()
    private(set) var isReady = false
    private(set) var isClosed = false

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ message: RemoteMessage) {
        guard isReady, !isClosed, let frame = try? RemoteFrame.encode(message) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Sends a last message and closes once it has been handed to the network.
    func finish(with message: RemoteMessage) {
        guard isReady, !isClosed, let frame = try? RemoteFrame.encode(message) else { return close() }
        connection.send(content: frame, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    func close(_ error: NWError? = nil) {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let callback = onClose
        onClose = nil; onMessage = nil; onReady = nil
        callback?(error, isReady)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            guard !isReady else { return }
            isReady = true
            onReady?()
            receive()
        case .failed(let error): close(error)
        // TLS failures surface as `waiting` on the client; retrying cannot help.
        case .waiting(let error): close(error)
        case .cancelled: close()
        default: break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated { self?.received(data, complete: complete, error: error) }
        }
    }

    private func received(_ data: Data?, complete: Bool, error: NWError?) {
        guard !isClosed else { return }
        if let data, !data.isEmpty {
            do {
                for body in try decoder.append(data) {
                    if let message = RemoteFrame.decode(body) { onMessage?(message) }
                    if isClosed { return }
                }
            } catch { return close() }
        }
        if let error { return close(error) }
        if complete { return close() }
        receive()
    }
}

extension NWError {
    var isTLSFailure: Bool { if case .tls = self { true } else { false } }
}
