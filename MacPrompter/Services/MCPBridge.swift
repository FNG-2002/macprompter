import Foundation

/// stdio ↔ HTTP bridge for MCP clients that only start local programs
/// (Claude Desktop, Cowork). Runs in the sandboxed helper `macprompter-mcp`;
/// the app compiles it too for its constants and the tests.
actor MCPBridge {
    nonisolated static let tokenVariable = "MACPROMPTER_MCP_TOKEN"
    nonisolated static let portVariable = "MACPROMPTER_MCP_PORT"
    nonisolated static let defaultPort: UInt16 = 47823
    nonisolated static let helperPath = "Contents/Helpers/macprompter-mcp"
    nonisolated static let unreachableMessage = "macprompter ist nicht erreichbar. Starte macprompter und schalte unter Einstellungen → KI-Agenten den Zugriff für KI-Agenten (MCP) ein."
    nonisolated static let unauthorizedMessage = "macprompter hat den Token abgelehnt. Kopiere die Konfiguration für Claude Desktop erneut aus macprompter (Einstellungen → KI-Agenten → Einrichten) und starte Claude neu."

    /// Sends one HTTP request and returns body and status code.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    /// Starts macprompter if it is not running; false when it already runs
    /// (then MCP is switched off and waiting would not help).
    typealias Launcher = @Sendable () async -> Bool

    enum ConfigurationError: Error, CustomStringConvertible {
        case missingToken, invalidPort(String)
        var description: String {
            switch self {
            case .missingToken: "\(MCPBridge.tokenVariable) fehlt. Kopiere die Konfiguration aus macprompter (Einstellungen → KI-Agenten)."
            case .invalidPort(let value): "\(MCPBridge.portVariable) ist kein gültiger Port: \(value)"
            }
        }
    }

    nonisolated let endpoint: URL
    private let token: String
    private let transport: Transport
    private let launcher: Launcher?
    private let launchTimeout: Duration
    private let retryInterval: Duration
    private var launch: (started: Task<Bool, Never>, deadline: ContinuousClock.Instant)?

    init(environment: [String: String], transport: @escaping Transport = MCPBridge.urlSession,
         launcher: Launcher? = nil, launchTimeout: Duration = .seconds(15), retryInterval: Duration = .milliseconds(250)) throws {
        guard let token = environment[Self.tokenVariable]?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            throw ConfigurationError.missingToken
        }
        var port = Self.defaultPort
        if let value = environment[Self.portVariable], !value.isEmpty {
            guard let parsed = UInt16(value), parsed > 0 else { throw ConfigurationError.invalidPort(value) }
            port = parsed
        }
        endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!
        self.token = token
        self.transport = transport
        self.launcher = launcher
        self.launchTimeout = launchTimeout
        self.retryInterval = retryInterval
    }

    /// One newline-delimited JSON-RPC message in, the reply line out (nil for
    /// notifications and responses, which get none).
    func forward(_ line: String) async -> Data? {
        let body = Data(line.utf8)
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: body), message.object != nil else {
            return Self.error(id: .null, code: -32700, "Parse error")
        }
        let id = message["method"] == nil ? nil : message["id"].flatMap { $0 == .null ? nil : $0 }
        let failure: String
        do {
            let (data, status) = try await send(body)
            switch status {
            case 200 where !data.isEmpty: return id == nil ? nil : data
            case 202: return nil
            case 401: failure = Self.unauthorizedMessage
            default: failure = "macprompter antwortete mit HTTP \(status)."
            }
        } catch {
            failure = Self.unreachableMessage
        }
        return id.map { Self.error(id: $0, code: -32000, failure) }
    }

    private func send(_ body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            return try await transport(request)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            // The agent asked for macprompter: start it and wait for its server.
            guard let deadline = await launchDeadline() else { throw error }
            while true {
                try await Task.sleep(for: retryInterval)
                do { return try await transport(request) } catch let error as URLError where error.code == .cannotConnectToHost {
                    if ContinuousClock.now >= deadline { throw error }
                }
            }
        }
    }

    /// One launch per wait window: concurrent requests and requests while the
    /// app is still starting wait for the same launch instead of starting it again.
    private func launchDeadline() async -> ContinuousClock.Instant? {
        guard let launcher else { return nil }
        let current: (started: Task<Bool, Never>, deadline: ContinuousClock.Instant)
        if let launch, ContinuousClock.now < launch.deadline { current = launch } else {
            current = (Task { await launcher() }, ContinuousClock.now + launchTimeout)
            launch = current
        }
        return await current.started.value ? current.deadline : nil
    }

    nonisolated static let urlSession: Transport = { request in
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }()

    nonisolated static func error(id: JSONValue, code: Int, _ message: String) -> Data {
        (["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]] as JSONValue).data
    }
}
