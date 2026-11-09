import XCTest
import SwiftUI
import Network
import CryptoKit
@testable import MacPrompter

final class RemoteProtocolTests: XCTestCase {
    func testFramesSurviveArbitraryChunking() throws {
        let messages: [RemoteMessage] = [.command(.nudge(-80)), .status(RemoteStatus(scriptTitle: "Grüße 👋", isVisible: true)), .challenge(nonce: Data([1, 2, 3]))]
        let stream = try messages.map(RemoteFrame.encode).reduce(Data(), +)
        var decoder = RemoteFrameDecoder()
        var decoded: [RemoteMessage] = []
        for byte in stream { decoded += try decoder.append(Data([byte])).compactMap(RemoteFrame.decode) }
        XCTAssertEqual(decoded, messages)
        var whole = RemoteFrameDecoder()
        XCTAssertEqual(try whole.append(stream).compactMap(RemoteFrame.decode), messages)
    }

    func testOversizedFrameIsRejected() {
        var decoder = RemoteFrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0x7f, 0, 0, 0, 1])))
    }

    func testUnknownMessageFromNewerPeerIsSkipped() {
        XCTAssertNil(RemoteFrame.decode(Data(#"{"futureCase":{}}"#.utf8)))
        XCTAssertEqual(RemoteFrame.decode(Data(#"{"command":{"_0":{"stepSlide":{"_0":1}}}}"#.utf8)), .command(.stepSlide(1)))
    }

    func testScrollAccumulatorCoalescesAndFollowsFinger() {
        var accumulator = RemoteScrollAccumulator()
        XCTAssertEqual(accumulator.add(-10, at: 0), 20, "finger up advances the text")
        XCTAssertNil(accumulator.add(-5, at: 0.01))
        XCTAssertNil(accumulator.add(-5, at: 0.02))
        XCTAssertEqual(accumulator.add(2, at: 0.04), 16)
        XCTAssertNil(accumulator.flush(at: 0.05, force: true))
        XCTAssertEqual(accumulator.add(-1000, at: 1), RemoteProtocol.nudgeLimit)
    }

    func testScrollHintMirrorsTheGate() {
        var status = RemoteStatus(isVisible: true)
        XCTAssertTrue(status.canScroll)
        XCTAssertNil(status.scrollHint)
        status.countdown = 2
        XCTAssertEqual(status.scrollHint, "Countdown läuft.")
        status.isHovering = true
        XCTAssertFalse(status.canScroll)
        XCTAssertEqual(status.scrollHint, "Hover-Pause am Mac hat Vorrang.")
        status.isVisible = false
        XCTAssertEqual(status.scrollHint, "Der Prompter ist ausgeblendet.")
    }

    func testPairingCodesAreSixDigits() {
        var generator = SeededGenerator(seed: 7)
        let codes = (0..<200).map { _ in RemotePairing.makeCode(using: &generator) }
        XCTAssertTrue(codes.allSatisfy(RemotePairing.isValidCode))
        XCTAssertGreaterThan(Set(codes).count, 190)
        XCTAssertFalse(RemotePairing.isValidCode("12345"))
        XCTAssertFalse(RemotePairing.isValidCode("12345a"))
        XCTAssertFalse(RemotePairing.isValidCode("١٢٣٤٥٦"))
    }

    func testPairingKeyDependsOnCodeAndSalt() {
        let salt = Data(repeating: 1, count: 16)
        let key = RemotePairing.pairingKey(code: "123456", salt: salt, iterations: 1000)
        XCTAssertEqual(key.count, 32)
        XCTAssertEqual(key, RemotePairing.pairingKey(code: "123456", salt: salt, iterations: 1000))
        XCTAssertNotEqual(key, RemotePairing.pairingKey(code: "123457", salt: salt, iterations: 1000))
        XCTAssertNotEqual(key, RemotePairing.pairingKey(code: "123456", salt: Data(repeating: 2, count: 16), iterations: 1000))
    }

    func testProofBindsKeyNonceAndPurpose() {
        let key = RemotePairing.randomBytes(32), nonce = RemotePairing.randomBytes(32)
        let proof = RemotePairing.proof(key: key, nonce: nonce, label: RemoteProtocol.authLabel)
        XCTAssertTrue(RemotePairing.verify(proof, key: key, nonce: nonce, label: RemoteProtocol.authLabel))
        XCTAssertFalse(RemotePairing.verify(proof, key: key, nonce: nonce, label: RemoteProtocol.pairLabel))
        XCTAssertFalse(RemotePairing.verify(proof, key: key, nonce: RemotePairing.randomBytes(32), label: RemoteProtocol.authLabel))
        XCTAssertFalse(RemotePairing.verify(proof, key: RemotePairing.randomBytes(32), nonce: nonce, label: RemoteProtocol.authLabel))
    }

    func testBothSidesDeriveTheSameDeviceKeyWithoutSendingIt() throws {
        let mac = Curve25519.KeyAgreement.PrivateKey(), phone = Curve25519.KeyAgreement.PrivateKey()
        let pairingKey = RemotePairing.randomBytes(32), id = UUID()
        let macPub = mac.publicKey.rawRepresentation, phonePub = phone.publicKey.rawRepresentation
        let onMac = try RemotePairing.deviceKey(privateKey: mac, peerPublicKey: phonePub, pairingKey: pairingKey, deviceID: id, macPublicKey: macPub, phonePublicKey: phonePub)
        let onPhone = try RemotePairing.deviceKey(privateKey: phone, peerPublicKey: macPub, pairingKey: pairingKey, deviceID: id, macPublicKey: macPub, phonePublicKey: phonePub)
        XCTAssertEqual(onMac, onPhone)
        XCTAssertEqual(onMac.count, 32)
        // A recorded pairing (public keys + broken code) is not enough without a private key.
        let eavesdropper = Curve25519.KeyAgreement.PrivateKey()
        XCTAssertNotEqual(onMac, try RemotePairing.deviceKey(privateKey: eavesdropper, peerPublicKey: macPub, pairingKey: pairingKey, deviceID: id, macPublicKey: macPub, phonePublicKey: phonePub))
    }

    func testPairingWindowClosesAfterFailuresOrDeadline() {
        let start = Date()
        var window = RemotePairingWindow(code: "000111", salt: Data(count: 16), now: start, iterations: 1000)
        XCTAssertTrue(window.isOpen(at: start))
        XCTAssertFalse(window.isOpen(at: start.addingTimeInterval(RemoteProtocol.pairingDuration)))
        for attempt in 1..<RemoteProtocol.maxPairingFailures { XCTAssertTrue(window.registerFailure(at: start), "attempt \(attempt)") }
        XCTAssertFalse(window.registerFailure(at: start))
        XCTAssertEqual(window.remainingAttempts, 0)
    }
}

@MainActor
final class RemoteBridgeTests: XCTestCase {
    private func makeBridge() -> RemoteBridge {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let library = ScriptLibrary(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        // A new library starts empty; give the bridge two scripts to work with.
        library.add(title: Script.english.title, body: Script.english.body, language: .english)
        library.add(title: Script.welcome.title, body: Script.welcome.body)
        return RemoteBridge(session: PrompterSession(preferences: preferences), preferences: preferences, library: library)
    }

    func testStartPresentsSelectedScriptAndPauseHideStopIt() {
        let bridge = makeBridge()
        bridge.perform(.start)
        XCTAssertTrue(bridge.session.gate.isVisible)
        XCTAssertTrue(bridge.session.gate.isPlaying)
        XCTAssertEqual(bridge.session.script.id, bridge.library.selectedID)
        bridge.perform(.start)
        XCTAssertTrue(bridge.session.gate.isPlaying, "start is idempotent instead of toggling")
        bridge.perform(.pause)
        XCTAssertFalse(bridge.session.gate.isPlaying)
        bridge.perform(.hide)
        XCTAssertFalse(bridge.session.gate.isVisible)
    }

    func testNudgeRespectsThePlaybackGate() {
        let bridge = makeBridge()
        bridge.perform(.start)
        bridge.perform(.pause)
        bridge.session.maximumOffset = 1000
        bridge.session.setHover(true)
        bridge.perform(.nudge(120))
        XCTAssertEqual(bridge.session.offset, 0, "hover must win over the iPhone")
        bridge.session.setHover(false)
        bridge.perform(.nudge(120))
        XCTAssertEqual(bridge.session.offset, 120)
        bridge.perform(.nudge(-.infinity))
        bridge.perform(.nudge(-5000))
        XCTAssertEqual(bridge.session.offset, 0, "non-finite input is ignored, large steps are clamped")
        bridge.perform(.hide)
        bridge.perform(.nudge(50))
        XCTAssertEqual(bridge.session.offset, 0)
    }

    func testSpeedAndModeAreClampedToTheMacSettings() {
        let bridge = makeBridge()
        bridge.perform(.setSpeed(500))
        XCTAssertEqual(bridge.preferences.value.speed, 120)
        bridge.perform(.setSpeed(41.6))
        XCTAssertEqual(bridge.preferences.value.speed, 42)
        bridge.perform(.setSpeed(.nan))
        XCTAssertEqual(bridge.preferences.value.speed, 42)
        bridge.perform(.setMode(.voice))
        XCTAssertEqual(bridge.preferences.value.mode, .voice)
        XCTAssertEqual(bridge.status().mode, .voice)
    }

    func testSelectingScriptSwitchesVisiblePrompter() throws {
        let bridge = makeBridge()
        let other = try XCTUnwrap(bridge.library.scripts.last)
        bridge.perform(.start)
        bridge.perform(.selectScript(other.id))
        XCTAssertEqual(bridge.library.selectedID, other.id)
        XCTAssertEqual(bridge.session.script.id, other.id)
        XCTAssertFalse(bridge.session.gate.isPlaying)
        bridge.perform(.selectScript(UUID()))
        XCTAssertEqual(bridge.library.selectedID, other.id)
    }

    func testStatusCarriesTitlesButNeverScriptText() throws {
        let bridge = makeBridge()
        bridge.perform(.start)
        let status = bridge.status()
        XCTAssertEqual(status.scriptTitle, bridge.session.script.title)
        XCTAssertNil(status.slides)
        let json = String(decoding: try JSONEncoder().encode([RemoteMessage.status(status), .scripts(bridge.scripts())]), as: UTF8.self)
        for script in bridge.library.scripts {
            XCTAssertTrue(json.contains(script.title))
            XCTAssertFalse(json.contains(String(script.body.prefix(30))))
        }
    }

    func testSlidesFollowTheSessionAndRespectHover() throws {
        var bridge = makeBridge()
        var presenting = false
        bridge.isPresenting = { presenting }
        bridge.setPresenting = { presenting = $0 }
        bridge.perform(.start)
        XCTAssertNil(bridge.status().slides, "plain scripts report no deck")
        bridge.perform(.stepSlide(1)); bridge.perform(.startPresentation)
        XCTAssertFalse(presenting)

        var deck = PresentationDeck(fileName: "Talk.pdf", pages: ["A", "B", "C"].map { SlidePage(text: $0, imageHash: 0) })
        for (index, text) in ["Hallo zusammen heute", "Unsere Zahlen steigen", "Vielen Dank"].enumerated() { deck.sections[index].text = text }
        var script = Script(title: "Talk", body: PresentationComposer.compose(deck).body)
        script.presentation = deck
        bridge.library.scripts.append(script)
        bridge.perform(.selectScript(script.id))
        XCTAssertEqual(bridge.status().slides, RemoteSlides(current: 0, count: 3, isPresenting: false, slide: 0, slideCount: 3, step: 0, steps: 1))
        bridge.session.maximumOffset = 1000
        bridge.perform(.stepSlide(4))
        XCTAssertEqual(bridge.status().slides?.current, 1, "one step per command, like the arrow keys")
        XCTAssertNotNil(bridge.session.jumpCharacter)
        bridge.session.setHover(true)
        bridge.session.resolveJump(300, for: try XCTUnwrap(bridge.session.jumpCharacter))
        XCTAssertEqual(bridge.session.offset, 0, "hover keeps the text still")
        bridge.perform(.stepSlide(-1)); bridge.perform(.stepSlide(-1)); bridge.perform(.stepSlide(0))
        XCTAssertEqual(bridge.status().slides?.current, 0)
        bridge.perform(.startPresentation)
        XCTAssertEqual(bridge.status().slides?.isPresenting, true)
        bridge.perform(.endPresentation)
        XCTAssertFalse(presenting)
    }

    func testLegacyPreferencesKeepRemoteControlOff() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let original = PreferenceStore(defaults: defaults)
        original.value.speed = 55
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "preferences.v1"))) as? [String: Any])
        XCTAssertNil(dictionary["remoteEnabled"])
        let restored = PreferenceStore(defaults: defaults)
        XCTAssertEqual(restored.value.speed, 55)
        XCTAssertFalse(restored.value.remoteControlEnabled)
        restored.value.remoteControlEnabled = true
        XCTAssertTrue(PreferenceStore(defaults: defaults).value.remoteControlEnabled)
    }
}

@MainActor
final class RemoteServerTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func testUnreadableDeviceListIsNeverOverwritten() throws {
        let file = folder.appending(path: "remote-devices.json")
        let original = Data("not json".utf8)
        try original.write(to: file)
        let server = RemoteServer(directory: folder)
        XCTAssertNotNil(server.errorMessage)
        XCTAssertTrue(server.devices.isEmpty)
        server.revoke(UUID())
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testDisabledServerDoesNotListen() {
        let server = RemoteServer(directory: folder)
        server.beginPairing()
        XCTAssertNil(server.pairing)
        XCTAssertFalse(server.isAdvertising)
        XCTAssertNil(server.port)
    }

    /// Full loopback run: TLS-PSK pairing, authenticated commands, status push,
    /// wrong-code accounting and revocation – the same code the iPhone uses.
    func testPairCommandAndRevokeOverLoopback() async throws {
        let preferences = PreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let library = ScriptLibrary(directory: folder)
        library.add(title: Script.welcome.title, body: Script.welcome.body)
        let session = PrompterSession(preferences: preferences)
        let server = RemoteServer(directory: folder)
        server.bridge = RemoteBridge(session: session, preferences: preferences, library: library)
        server.setEnabled(true)
        defer { server.setEnabled(false) }
        try await waitUntil { server.port != nil }
        server.beginPairing()
        try await waitUntil { server.port != nil && server.pairing != nil }
        let window = try XCTUnwrap(server.pairing)
        let store = MemoryPairedMacStore()
        let client = RemoteClient(store: store)
        client.retryDelay = .milliseconds(150)
        func target() -> RemoteClient.DiscoveredMac {
            RemoteClient.DiscoveredMac(name: "Test-Mac", endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port!)!),
                serverID: server.serverID, pairingSalt: window.salt)
        }

        let intruder = RemoteClient(store: MemoryPairedMacStore())
        let wrong = window.code == "000000" ? "000001" : "000000"
        await intruder.pair(target(), code: wrong)
        try await waitUntil { if case .failed = intruder.phase { true } else { false } }
        try await waitUntil { server.pairing?.remainingAttempts == RemoteProtocol.maxPairingFailures - 1 }
        XCTAssertTrue(server.devices.isEmpty)

        await client.pair(target(), code: window.code)
        try await waitUntil(timeout: 20) { client.isConnected }
        XCTAssertNil(server.pairing, "a successful pairing closes the window")
        XCTAssertEqual(server.devices.count, 1)
        XCTAssertEqual(store.macs.first?.key, server.devices.first?.key)
        let device = try XCTUnwrap(server.devices.first)
        XCTAssertEqual(server.connectedDeviceIDs, [device.id])
        try await waitUntil { client.status != nil && !client.scripts.isEmpty }
        XCTAssertEqual(client.scripts.map(\.title), library.scripts.map(\.title))

        client.send(.setSpeed(77))
        try await waitUntil { preferences.value.speed == 77 && client.status?.speed == 77 }
        client.send(.start)
        try await waitUntil { client.status?.isVisible == true && session.gate.isPlaying }

        // The closed window refuses the same code again.
        let late = RemoteClient(store: MemoryPairedMacStore())
        await late.pair(target(), code: window.code)
        try await waitUntil { if case .failed = late.phase { true } else { false } }
        XCTAssertEqual(server.devices.count, 1)

        server.revoke(device.id)
        try await waitUntil { !client.isConnected }
        XCTAssertTrue(server.connectedDeviceIDs.isEmpty)
        client.connect(target())
        try await waitUntil { if case .failed = client.phase { true } else { false } }
        XCTAssertFalse(client.isConnected, "a revoked key is refused at the TLS layer")
    }

    /// Renders the real settings section with an open pairing window and two
    /// paired devices; the PNG lands in the test host's temporary folder.
    func testSettingsSectionRenders() async throws {
        let now = Date.now.timeIntervalSinceReferenceDate
        let stored = #"{"serverID":"8C3E1D7A-4F1B-4E0B-9C55-2B1D7A0E9F11","devices":[{"id":"0B7C2C5E-8D0F-4C3A-9A51-6A3C0D2E1F00","name":"iPhone","key":"AAAA","pairedAt":\#(now - 3 * 86400),"lastSeen":\#(now - 600)}]}"#
        try Data(stored.utf8).write(to: folder.appending(path: "remote-devices.json"))
        let server = RemoteServer(directory: folder)
        server.pairingIterations = 1000
        server.setEnabled(true)
        defer { server.setEnabled(false) }
        try await waitUntil { server.isAdvertising }
        server.beginPairing()
        let view = Form { RemoteSettingsSections(remote: server, isEnabled: .constant(true)) }
            .formStyle(.grouped).frame(width: 560, height: 720).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 720)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1000)
        let url = FileManager.default.temporaryDirectory.appending(path: "macprompter-remote-settings.png")
        try data.write(to: url)
        print("REMOTE_SNAPSHOT: \(url.path)")
    }

    private func waitUntil(timeout: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within \(timeout) s") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class MemoryPairedMacStore: PairedMacStoring {
    var macs: [PairedMac] = []
    func load() -> [PairedMac] { macs }
    func save(_ macs: [PairedMac]) { self.macs = macs }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
