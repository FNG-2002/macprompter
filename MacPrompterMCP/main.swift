import AppKit
import Foundation

// macprompter-mcp: stdio MCP server for Claude Desktop and Cowork. Forwards
// each line to the MCP endpoint of the running app on 127.0.0.1. Nothing but
// JSON-RPC may be written to stdout.

/// The app this helper is embedded in (…/macprompter.app/Contents/Helpers/macprompter-mcp).
let appURL: URL? = {
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}()

let bridge: MCPBridge
do {
    bridge = try MCPBridge(environment: ProcessInfo.processInfo.environment, launcher: { [appURL] in
        guard let appURL else { return false }
        let identifier = Bundle(url: appURL)?.bundleIdentifier ?? ""
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)) != nil
    })
} catch {
    FileHandle.standardError.write(Data("macprompter-mcp: \(error)\n".utf8))
    exit(64)
}

actor Output {
    func write(_ line: Data) {
        try? FileHandle.standardOutput.write(contentsOf: line + Data([0x0A]))
    }
}

let lines = AsyncStream<String> { continuation in
    Thread.detachNewThread {
        while let line = readLine() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { continuation.yield(line) }
        }
        continuation.finish()
    }
}

let output = Output()
await withTaskGroup(of: Void.self) { group in
    for await line in lines {
        group.addTask {
            if let reply = await bridge.forward(line) { await output.write(reply) }
        }
    }
}
