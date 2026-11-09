import Foundation
import Network
import Observation

struct HTTPRequest: Sendable, Equatable {
    var method: String
    var path: String
    var headers: [String: String]   // lowercased names
    var body: Data
}

struct HTTPResponse: Sendable, Equatable {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ value: JSONValue, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: value.data)
    }

    var serialized: Data {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                       404: "Not Found", 405: "Method Not Allowed", 411: "Length Required", 413: "Payload Too Large"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// Incremental HTTP/1.1 request parser; only what MCP clients send.
struct HTTPRequestParser {
    static let maxHeader = 16 * 1024
    static let maxBody = 64 * 1024 * 1024
    enum Result: Equatable { case incomplete, request(HTTPRequest), error(Int) }
    private var buffer = Data()

    mutating func append(_ data: Data) -> Result {
        buffer.append(data)
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > Self.maxHeader ? .error(413) : .incomplete
        }
        guard let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return .error(400) }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .error(400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .error(400) }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .error(411) }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .error(400) }
        guard length <= Self.maxBody else { return .error(413) }
        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let path = String(parts[1].split(separator: "?", maxSplits: 1).first ?? "")
        return .request(HTTPRequest(method: String(parts[0]), path: path, headers: headers,
            body: Data(buffer[bodyStart..<bodyStart + length])))
    }
}

/// MCP endpoint for AI agents (Streamable HTTP, JSON responses). Opt-in,
/// bound to 127.0.0.1 and protected by a bearer token that only the user
/// copies into an agent's configuration.
@MainActor @Observable
final class MCPServer {
    struct Call: Identifiable, Equatable {
        let id = UUID()
        let tool: String
        let date: Date
        let succeeded: Bool
    }
    private struct Stored: Codable {
        var token: String
        var folderBookmark: Data?
    }

    nonisolated static let defaultPort = MCPBridge.defaultPort
    static let path = "/mcp"
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]

    private(set) var isRunning = false
    private(set) var port: UInt16 = MCPServer.defaultPort
    private(set) var errorMessage: String?
    private(set) var token: String
    private(set) var folder: URL?
    private(set) var recentCalls: [Call] = []
    @ObservationIgnored var tools: AgentTools?
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var folderBookmark: Data?
    @ObservationIgnored private var listener: NWListener?

    init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "macprompter", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "mcp.json")
        var stored: Stored?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            stored = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
            if stored == nil {
                canSave = false
                errorMessage = "Die MCP-Einstellungen konnten nicht gelesen werden und bleiben unverändert: \(fileURL.path)"
            }
        }
        token = stored?.token ?? Self.makeToken()
        folderBookmark = stored?.folderBookmark
        self.folder = resolveFolder()
        if stored == nil { save() }
    }

    var endpoint: String { "http://127.0.0.1:\(port)\(Self.path)" }

    static func makeToken() -> String {
        RemotePairing.randomBytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func regenerateToken() {
        token = Self.makeToken()
        save()
    }

    func setFolder(_ url: URL?) {
        folderBookmark = url.flatMap { try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        folder = url == nil ? nil : resolveFolder()
        if url != nil && folder == nil { errorMessage = "Der Ordner konnte nicht dauerhaft freigegeben werden." }
        save()
    }

    private func resolveFolder() -> URL? {
        guard let folderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folderBookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            self.folderBookmark = fresh
        }
        return url
    }

    private func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Stored(token: token, folderBookmark: folderBookmark)).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { errorMessage = "MCP-Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" }
    }

    // MARK: Listener

    func configure(enabled: Bool, port: UInt16) {
        guard enabled != isRunning || port != self.port || (enabled && listener == nil) else { return }
        stop()
        self.port = port
        if enabled { start() }
    }

    private func stop() {
        listener?.cancel(); listener = nil
        isRunning = false
    }

    private func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        // Loopback only: never reachable from the network.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self, listener === self.listener else { return }
                    switch state {
                    case .ready: self.isRunning = true; if self.canSave { self.errorMessage = nil }
                    case .failed(let error), .waiting(let error):
                        self.isRunning = false
                        self.errorMessage = "Port \(self.port) ist nicht verfügbar: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            errorMessage = "Der MCP-Zugang konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, parser: HTTPRequestParser())
    }

    private func receive(_ connection: NWConnection, parser: HTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var parser = parser
                switch parser.append(data ?? Data()) {
                case .incomplete:
                    if complete || error != nil { connection.cancel() } else { self.receive(connection, parser: parser) }
                case .error(let status):
                    self.send(HTTPResponse(status: status), on: connection)
                case .request(let request):
                    Task { @MainActor in self.send(await self.respond(to: request), on: connection) }
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: HTTP → JSON-RPC

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        guard request.path == Self.path else { return HTTPResponse(status: 404) }
        // DNS rebinding: browsers send Origin/Host of the attacking site.
        if let origin = request.headers["origin"], !Self.isLocal(URL(string: origin)?.host) { return HTTPResponse(status: 403) }
        if let host = request.headers["host"], !Self.isLocal(host.split(separator: ":").first.map(String.init)) { return HTTPResponse(status: 403) }
        guard request.headers["authorization"].map({ Self.constantTimeEqual($0, "Bearer \(token)") }) == true else {
            return HTTPResponse(status: 401, headers: ["WWW-Authenticate": "Bearer"])
        }
        guard request.method == "POST" else { return HTTPResponse(status: 405, headers: ["Allow": "POST"]) }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: request.body), message.object != nil else {
            return .json(Self.error(id: .null, code: -32700, "Parse error"), status: 400)
        }
        guard let reply = await handle(message) else { return HTTPResponse(status: 202) }
        return .json(reply)
    }

    private static func isLocal(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// nil for notifications and responses, which get 202 Accepted.
    func handle(_ message: JSONValue) async -> JSONValue? {
        guard let method = message["method"]?.string else { return nil }
        guard let id = message["id"], id != .null else { return nil }
        let params = message["params"] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.string ?? ""
            return Self.result(id: id, [
                "protocolVersion": .string(Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0]),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "macprompter", "title": "macprompter",
                               "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")],
                "instructions": "Teleprompter-Bibliothek von macprompter. Skripte und Präsentationen anlegen und bearbeiten; Text pro Folie ist der Sprechtext, den macprompter beim Präsentieren zeigt. [Klammern] sind Regieanweisungen, [Weiter] wechselt innerhalb einer Folie zum nächsten Aufdeck-Schritt. Löschen ist bewusst nicht möglich.",
            ])
        case "ping": return Self.result(id: id, [:])
        case "tools/list": return Self.result(id: id, ["tools": .array(AgentTools.definitions)])
        case "tools/call":
            guard let name = params["name"]?.string else { return Self.error(id: id, code: -32602, "Missing tool name") }
            guard AgentTools.definitions.contains(where: { $0["name"]?.string == name }) else {
                return Self.error(id: id, code: -32602, "Unknown tool: \(name)")
            }
            guard let tools else { return Self.result(id: id, Self.toolResult(text: "macprompter ist nicht bereit.", isError: true)) }
            do {
                let value = try await tools.call(name, params["arguments"] ?? [:])
                log(name, succeeded: true)
                return Self.result(id: id, ["content": [["type": "text", "text": .string(value.text)]], "structuredContent": value, "isError": false])
            } catch {
                log(name, succeeded: false)
                let text = (error as? AgentTools.Failure)?.message ?? error.localizedDescription
                return Self.result(id: id, Self.toolResult(text: text, isError: true))
            }
        default: return Self.error(id: id, code: -32601, "Method not found: \(method)")
        }
    }

    private func log(_ tool: String, succeeded: Bool) {
        // Only tool names and times, never script content (privacy).
        recentCalls = Array(([Call(tool: tool, date: Date(), succeeded: succeeded)] + recentCalls).prefix(12))
    }

    private static func toolResult(text: String, isError: Bool) -> JSONValue {
        ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]
    }

    private static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: JSONValue, code: Int, _ message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}
