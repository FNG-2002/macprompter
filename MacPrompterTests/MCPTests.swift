import XCTest
import SwiftUI
@testable import MacPrompter

final class HTTPParserTests: XCTestCase {
    func testParsesRequestAcrossChunks() {
        var parser = HTTPRequestParser()
        let raw = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:47823\r\nContent-Length: 5\r\nAuthorization: Bearer abc\r\n\r\nhello"
        let data = Data(raw.utf8)
        XCTAssertEqual(parser.append(data.prefix(20)), .incomplete)
        XCTAssertEqual(parser.append(data.dropFirst(20).dropLast(2)), .incomplete)
        guard case .request(let request) = parser.append(data.suffix(2)) else { return XCTFail("expected request") }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.body, Data("hello".utf8))
    }

    func testRejectsChunkedOversizedAndGarbage() {
        var chunked = HTTPRequestParser()
        XCTAssertEqual(chunked.append(Data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)), .error(411))
        var large = HTTPRequestParser()
        XCTAssertEqual(large.append(Data("POST /mcp HTTP/1.1\r\nContent-Length: \(HTTPRequestParser.maxBody + 1)\r\n\r\n".utf8)), .error(413))
        var garbage = HTTPRequestParser()
        XCTAssertEqual(garbage.append(Data("hello\r\n\r\n".utf8)), .error(400))
        var header = HTTPRequestParser()
        XCTAssertEqual(header.append(Data(repeating: 65, count: HTTPRequestParser.maxHeader + 1)), .error(413))
    }
}

@MainActor
final class MCPServerTests: XCTestCase {
    private var folder: URL!
    private var server: MCPServer!
    private var library: ScriptLibrary!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        library = ScriptLibrary(directory: folder)
        server = MCPServer(directory: folder)
        let tools = AgentTools(library: library, files: PresentationFiles(folder: folder.appending(path: "Presentations")))
        tools.pdfFolder = { [server] in server?.folder }
        server.tools = tools
    }

    override func tearDown() async throws {
        server.configure(enabled: false, port: server.port)
        try? FileManager.default.removeItem(at: folder)
    }

    private func request(_ body: JSONValue?, method: String = "POST", headers: [String: String] = [:], token: String? = nil) async -> HTTPResponse {
        var all = ["host": "127.0.0.1:47823", "authorization": "Bearer \(token ?? server.token)"]
        all.merge(headers) { $1 }
        return await server.respond(to: HTTPRequest(method: method, path: "/mcp", headers: all, body: body?.data ?? Data()))
    }

    private func call(_ tool: String, _ arguments: JSONValue = [:]) async throws -> (value: JSONValue, isError: Bool) {
        let response = await request(["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": .string(tool), "arguments": arguments]])
        XCTAssertEqual(response.status, 200)
        let reply = try JSONDecoder().decode(JSONValue.self, from: response.body)
        let result = try XCTUnwrap(reply["result"])
        let isError = result["isError"] == .bool(true)
        return (isError ? result["content"]?.array?.first?["text"] ?? .null : result["structuredContent"] ?? .null, isError)
    }

    func testAccessIsGuarded() async {
        let ping: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "ping"]
        var statuses: [Int] = []
        statuses.append(await request(ping, token: "falsch").status)
        statuses.append(await request(ping, headers: ["origin": "https://evil.example"]).status)
        statuses.append(await request(ping, headers: ["host": "evil.example:47823"]).status)
        statuses.append(await request(ping, headers: ["origin": "http://localhost:3000"]).status)
        statuses.append(await request(nil, method: "GET").status)
        statuses.append(await server.respond(to: HTTPRequest(method: "POST", path: "/other", headers: [:], body: Data())).status)
        statuses.append(await request(["jsonrpc": "2.0", "method": "notifications/initialized"]).status)
        statuses.append(await server.respond(to: HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(server.token)"], body: Data("{".utf8))).status)
        XCTAssertEqual(statuses, [401, 403, 403, 200, 405, 404, 202, 400])
    }

    func testInitializeNegotiatesVersionAndListsSafeTools() async throws {
        let reply = try JSONDecoder().decode(JSONValue.self, from: await request(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]]).body)
        XCTAssertEqual(reply["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(reply["result"]?["serverInfo"]?["name"], "macprompter")
        let future = try JSONDecoder().decode(JSONValue.self, from: await request(
            ["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "2099-01-01"]]).body)
        XCTAssertEqual(future["result"]?["protocolVersion"]?.string, MCPServer.protocolVersions[0])

        let list = try JSONDecoder().decode(JSONValue.self, from: await request(["jsonrpc": "2.0", "id": 3, "method": "tools/list"]).body)
        let names = list["result"]?["tools"]?.array?.compactMap { $0["name"]?.string } ?? []
        XCTAssertTrue(names.contains("create_presentation"))
        XCTAssertTrue(names.contains("set_slide_text"))
        XCTAssertFalse(names.contains { $0.contains("delete") }, "agents must not delete scripts")
        for tool in list["result"]?["tools"]?.array ?? [] { XCTAssertEqual(tool["inputSchema"]?["type"], "object") }

        let unknown = try JSONDecoder().decode(JSONValue.self, from: await request(["jsonrpc": "2.0", "id": 4, "method": "resources/list"]).body)
        XCTAssertEqual(unknown["error"]?["code"], -32601)
        let badTool = try JSONDecoder().decode(JSONValue.self, from: await request(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "delete_script"]]).body)
        XCTAssertEqual(badTool["error"]?["code"], -32602)
    }

    func testCreateReadAndUpdateScript() async throws {
        let created = try await call("create_script", ["title": "Pitch", "text": "Hallo [Pause] Welt", "language": "en"])
        XCTAssertFalse(created.isError)
        let id = try XCTUnwrap(created.value["script_id"]?.string)
        XCTAssertEqual(library.scripts.first?.language, .english)
        let listed = try await call("list_scripts")
        XCTAssertEqual(listed.value["scripts"]?.array?.first?["words"], 2)
        _ = try await call("update_script", ["script_id": .string(id), "title": "Pitch v2", "text": "Neu"])
        let read = try await call("get_script", ["script_id": .string(id)])
        XCTAssertEqual(read.value["title"], "Pitch v2")
        XCTAssertEqual(read.value["text"], "Neu")
        XCTAssertEqual(read.value["language"], "en")
        _ = try await call("update_script", ["script_id": .string(id), "language": "tr"])
        XCTAssertEqual(library.scripts.first?.language.rawValue, "tr-TR")
        let turkish = try await call("get_script", ["script_id": .string(id)])
        XCTAssertEqual(turkish.value["language"], "tr")
        let invalid = try await call("update_script", ["script_id": .string(id), "language": "??"])
        XCTAssertTrue(invalid.isError)
        let missing = try await call("get_script", ["script_id": .string(UUID().uuidString)])
        XCTAssertTrue(missing.isError)
        let empty = try await call("create_script", ["title": " ", "text": "x"])
        XCTAssertTrue(empty.isError)
        XCTAssertEqual(server.recentCalls.first?.tool, "create_script")
        XCTAssertEqual(server.recentCalls.first?.succeeded, false)
    }

    func testPresentationWithStepsAndSlideTexts() async throws {
        let pdf = folder.appending(path: "Talk.pdf")
        try PresentationFileTests.makePDF(["Titel", "Punkt eins", "Punkt zwei", "Danke"], at: pdf)
        let base64 = try Data(contentsOf: pdf).base64EncodedString()
        let wrong = try await call("create_presentation", ["title": "Talk", "pdf_base64": .string(base64),
            "slides": [["text": "A"], ["text": "B", "steps": 2]]])
        XCTAssertTrue(wrong.isError, "steps must add up to the page count")
        XCTAssertTrue(library.scripts.isEmpty)

        let created = try await call("create_presentation", ["title": "Talk", "pdf_base64": .string(base64), "language": "de",
            "slides": [["text": "Willkommen"], ["text": "Erst eins. [Weiter] Dann zwei.", "steps": 2], ["text": "Danke"]]])
        XCTAssertFalse(created.isError, created.value.text)
        let id = try XCTUnwrap(created.value["script_id"]?.string)
        let slides = try XCTUnwrap(created.value["slides"]?.array)
        XCTAssertEqual(slides.count, 3)
        XCTAssertEqual(slides[1]["pdf_pages"], [2, 3])
        XCTAssertEqual(slides[1]["steps"], 2)
        XCTAssertTrue(library.scripts.first?.body.contains("[Start · Folie 2 · 2 Schritte]") == true)

        _ = try await call("set_slide_text", ["script_id": .string(id), "slide": 3, "text": "Vielen Dank!"])
        XCTAssertEqual(library.scripts.first?.presentation?.sections[2].text, "Vielen Dank!")
        let outOfRange = try await call("set_slide_text", ["script_id": .string(id), "slide": 9, "text": "x"])
        XCTAssertTrue(outOfRange.isError)
        let refused = try await call("update_script", ["script_id": .string(id), "text": "flach"])
        XCTAssertTrue(refused.isError)

        _ = try await call("set_slides", ["script_id": .string(id), "slides": [["text": "Hallo"], ["text": "Zwei"]]])
        XCTAssertEqual(library.scripts.first?.presentation?.sections.map(\.text), ["Hallo", "Zwei", "Vielen Dank!"])

        // A new version with an inserted page keeps all texts.
        try PresentationFileTests.makePDF(["Titel", "Agenda neu", "Punkt eins", "Punkt zwei", "Danke"], at: pdf)
        let replaced = try await call("replace_presentation_pdf", ["script_id": .string(id), "pdf_base64": .string(try Data(contentsOf: pdf).base64EncodedString())])
        XCTAssertFalse(replaced.isError, replaced.value.text)
        XCTAssertEqual(replaced.value["change"]?["added"], 1)
        XCTAssertEqual(library.scripts.first?.presentation?.sections.map(\.text), ["Hallo", "", "Zwei", "Vielen Dank!"])
    }

    func testPDFPathMustBeInsideSharedFolder() async throws {
        let noFolder = try await call("create_presentation", ["title": "X", "pdf_path": "/tmp/a.pdf"])
        XCTAssertTrue(noFolder.isError)
        XCTAssertTrue(noFolder.value.string?.contains("Ordner") == true)

        let shared = folder.appending(path: "Shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try PresentationFileTests.makePDF(["Eins", "Zwei"], at: shared.appending(path: "Deck.pdf"))
        try PresentationFileTests.makePDF(["Eins"], at: folder.appending(path: "Outside.pdf"))
        server.setFolder(shared)
        try XCTSkipIf(server.folder == nil, "security-scoped folder bookmark unavailable in this environment")
        let escape = try await call("create_presentation", ["title": "X", "pdf_path": "../Outside.pdf"])
        XCTAssertTrue(escape.isError)
        let created = try await call("create_presentation", ["title": "Deck", "pdf_path": "Deck.pdf", "slides": [["text": "A"], ["text": "B"]]])
        XCTAssertFalse(created.isError, created.value.text)
        XCTAssertEqual(library.scripts.first?.presentation?.pages.count, 2)
    }

    func testTokenIsPersistedPrivatelyAndNeverOverwrittenWhenUnreadable() throws {
        let token = server.token
        XCTAssertGreaterThanOrEqual(token.count, 40)
        let attributes = try FileManager.default.attributesOfItem(atPath: server.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(MCPServer(directory: folder).token, token)
        server.regenerateToken()
        XCTAssertNotEqual(server.token, token)

        try Data("kaputt".utf8).write(to: server.fileURL)
        let broken = MCPServer(directory: folder)
        XCTAssertNotNil(broken.errorMessage)
        broken.regenerateToken()
        XCTAssertEqual(try Data(contentsOf: server.fileURL), Data("kaputt".utf8))
    }

    /// Random ports can be taken (ephemeral range), so try a few.
    private func startListening() async throws -> UInt16 {
        for _ in 0..<5 {
            let port = UInt16.random(in: 49200...49900)
            server.configure(enabled: true, port: port)
            let deadline = Date().addingTimeInterval(5)
            while !server.isRunning && server.errorMessage?.contains("Port \(port) ") != true && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if server.isRunning { return port }
            server.configure(enabled: false, port: port)
        }
        XCTFail(server.errorMessage ?? "listener did not start")
        return 0
    }

    func testLoopbackHTTPEndToEnd() async throws {
        let port = try await startListening()
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = (["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "create_script", "arguments": ["title": "Per HTTP", "text": "Hallo"]]] as JSONValue).data
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data)["result"]?["isError"], false)
        XCTAssertEqual(library.scripts.first?.title, "Per HTTP")

        urlRequest.setValue("Bearer falsch", forHTTPHeaderField: "Authorization")
        let (_, denied) = try await URLSession.shared.data(for: urlRequest)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 401)
    }

    func testStdioBridgeEndToEnd() async throws {
        let port = try await startListening()
        let bridge = try MCPBridge(environment: [MCPBridge.tokenVariable: server.token, MCPBridge.portVariable: String(port)])
        let initialize = await bridge.forward(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let reply = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(initialize))
        XCTAssertEqual(reply["id"], 1)
        XCTAssertEqual(reply["result"]?["protocolVersion"], "2025-06-18")
        let notification = await bridge.forward(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification)
        let created = await bridge.forward((["jsonrpc": "2.0", "id": "b", "method": "tools/call", "params": ["name": "create_script", "arguments": ["title": "Per stdio", "text": "Hallo"]]] as JSONValue).text)
        let result = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(created))
        XCTAssertEqual(result["id"], "b")
        XCTAssertEqual(result["result"]?["isError"], false)
        XCTAssertEqual(library.scripts.first?.title, "Per stdio")
        XCTAssertFalse(String(decoding: try XCTUnwrap(created), as: UTF8.self).contains("\n"), "one message per line")

        let wrong = try MCPBridge(environment: [MCPBridge.tokenVariable: "falsch", MCPBridge.portVariable: String(port)])
        let rejected = await wrong.forward(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)
        let denied = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(rejected))
        XCTAssertEqual(denied["id"], 3)
        XCTAssertEqual(denied["error"]?["message"]?.string, MCPBridge.unauthorizedMessage)
    }

    func testClaudeDesktopConfigurationStartsTheEmbeddedHelper() throws {
        let helper = URL(filePath: "/Applications/mac prompter.app").appending(path: MCPBridge.helperPath)
        let text = MCPSettingsSections.claudeDesktopConfiguration(helper: helper, token: "abc", port: 50000)
        let server = try XCTUnwrap(JSONValue.parse(text)["mcpServers"]?["macprompter"])
        XCTAssertEqual(server["command"], "/Applications/mac prompter.app/Contents/Helpers/macprompter-mcp")
        let environment = try XCTUnwrap(server["env"]?.object?.compactMapValues(\.string))
        XCTAssertEqual(try MCPBridge(environment: environment).endpoint.absoluteString, "http://127.0.0.1:50000/mcp")
        XCTAssertEqual(environment[MCPBridge.tokenVariable], "abc")
    }

    func testSettingsRender() async throws {
        let view = Form {
            MCPSettingsSections(mcp: server, isEnabled: .constant(true), port: .constant(MCPServer.defaultPort), revealToken: true)
        }.formStyle(.grouped).frame(width: 540, height: 1100).preferredColorScheme(.dark)
        _ = try await call("list_scripts")
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 540, height: 1100)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1000)
        try data.write(to: FileManager.default.temporaryDirectory.appending(path: "macprompter-mcp-settings.png"))
    }
}

final class MCPBridgeTests: XCTestCase {
    private actor Counter {
        var requests = 0, launches = 0
        func request() -> Int { requests += 1; return requests }
        func launch() { launches += 1 }
    }
    private let environment = [MCPBridge.tokenVariable: "t"]
    private let pong = Data(#"{"id":1,"jsonrpc":"2.0","result":{}}"#.utf8)

    private func decode(_ data: Data?) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(data))
    }

    func testConfigurationFromEnvironment() throws {
        XCTAssertThrowsError(try MCPBridge(environment: [:]))
        XCTAssertThrowsError(try MCPBridge(environment: [MCPBridge.tokenVariable: " "]))
        XCTAssertThrowsError(try MCPBridge(environment: [MCPBridge.tokenVariable: "t", MCPBridge.portVariable: "70000"]))
        XCTAssertEqual(try MCPBridge(environment: environment).endpoint.absoluteString, "http://127.0.0.1:\(MCPServer.defaultPort)/mcp")
    }

    func testFailuresBecomeErrorsForRequestsOnly() async throws {
        let bridge = try MCPBridge(environment: environment, transport: { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
            XCTAssertEqual(request.httpMethod, "POST")
            return (Data(), 401)
        })
        let denied = try decode(await bridge.forward(#"{"jsonrpc":"2.0","id":5,"method":"ping"}"#))
        XCTAssertEqual(denied["id"], 5)
        XCTAssertEqual(denied["error"]?["message"]?.string, MCPBridge.unauthorizedMessage)
        let notification = await bridge.forward(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification)
        let garbage = try decode(await bridge.forward("kaputt"))
        XCTAssertEqual(garbage["id"], .null)
        XCTAssertEqual(garbage["error"]?["code"], -32700)
    }

    func testLaunchesTheAppOnceAndWaitsForItsServer() async throws {
        let counter = Counter()
        let bridge = try MCPBridge(environment: environment, transport: { [pong] _ in
            if await counter.request() <= 4 { throw URLError(.cannotConnectToHost) }
            return (pong, 200)
        }, launcher: { await counter.launch(); return true }, retryInterval: .milliseconds(5))
        async let first = bridge.forward(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        async let second = bridge.forward(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        let replies = try await [decode(first), decode(second)]
        XCTAssertEqual(replies.compactMap { $0["result"] }.count, 2)
        let launches = await counter.launches
        XCTAssertEqual(launches, 1)
    }

    func testDoesNotWaitWhenTheAppRunsWithMCPOffOrNeverComesUp() async throws {
        for started in [false, true] {
            let counter = Counter()
            let bridge = try MCPBridge(environment: environment, transport: { _ in
                _ = await counter.request()
                throw URLError(.cannotConnectToHost)
            }, launcher: { started }, launchTimeout: .milliseconds(50), retryInterval: .milliseconds(5))
            let reply = try decode(await bridge.forward(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#))
            XCTAssertEqual(reply["error"]?["message"]?.string, MCPBridge.unreachableMessage)
            let requests = await counter.requests
            if started { XCTAssertGreaterThan(requests, 1) } else { XCTAssertEqual(requests, 1) }
        }
    }
}
