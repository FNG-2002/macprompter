import Foundation

/// Wire format shared by the Mac app and macprompter Remote. Only titles and
/// playback state cross the link – never script bodies, audio or transcripts.
enum RemoteProtocol {
    static let serviceType = "_macprompter._tcp"
    static let version = 1
    static let pairingIdentity = "macprompter-pairing-v1"
    static let authLabel = "macprompter-auth-v1"
    static let pairLabel = "macprompter-pair-v1"
    static let maxFrameLength = 64 * 1024
    static let maxPairingFailures = 5
    static let pairingDuration: TimeInterval = 120
    static let speedRange = 10.0...120.0
    static let nudgeLimit = 400.0
    static let stepPoints = 80.0
}

enum RemoteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case voice, automatic, manual
    var id: Self { self }
    var title: String {
        switch self { case .voice: "Stimme"; case .automatic: "Automatisch"; case .manual: "Manuell" }
    }
    var symbol: String {
        switch self { case .voice: "waveform"; case .automatic: "forward.frame"; case .manual: "hand.draw" }
    }
}

struct RemoteScriptSummary: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
}

/// `current` is zero-based, matching the Mac's `SlideStatus`.
struct RemoteSlides: Codable, Equatable, Sendable {
    var current: Int
    var count: Int
    var isPresenting: Bool
    /// Slide and reveal step (a slide can span several PDF pages). Optional so
    /// either side may be older; nil falls back to pages.
    var slide: Int?
    var slideCount: Int?
    var step: Int?
    var steps: Int?

    var label: String {
        guard let slide, let slideCount, let step, let steps else { return "Folie \(current + 1) von \(count)" }
        return steps > 1 ? "Folie \(slide + 1) von \(slideCount) · Schritt \(step + 1)/\(steps)" : "Folie \(slide + 1) von \(slideCount)"
    }
}

struct RemoteStatus: Codable, Equatable, Sendable {
    var scriptID: UUID?
    var scriptTitle = ""
    var state = ""
    var isVisible = false
    var isPlaying = false
    var isHovering = false
    var isPreparing = false
    var countdown = 0
    var mode = RemoteMode.automatic
    var speed = 36.0
    var progress = 0.0
    var elapsedSeconds = 0
    /// nil while the current script has no slide deck.
    var slides: RemoteSlides?
    /// Mirrors `PlaybackGate.allowsMovement`; manual scrolling is ignored otherwise.
    var canScroll: Bool { isVisible && !isHovering && countdown == 0 }
    /// Why manual scrolling is currently locked, if it is.
    var scrollHint: String? {
        if !isVisible { return "Der Prompter ist ausgeblendet." }
        if isHovering { return "Hover-Pause am Mac hat Vorrang." }
        if countdown > 0 { return "Countdown läuft." }
        return nil
    }
}

enum RemoteCommand: Codable, Equatable, Sendable {
    case start, pause, hide
    case setSpeed(Double)
    case setMode(RemoteMode)
    case nudge(Double)
    case selectScript(UUID)
    case stepSlide(Int)
    case startPresentation, endPresentation
}

enum RemoteRejection: String, Codable, Sendable {
    case unknownDevice, pairingClosed, incompatibleVersion
}

enum RemoteMessage: Codable, Equatable, Sendable {
    // Mac → iPhone
    case challenge(nonce: Data)
    case welcome(macName: String, serverID: UUID)
    case paired(deviceID: UUID, serverID: UUID, macName: String, publicKey: Data)
    case rejected(RemoteRejection)
    case status(RemoteStatus)
    case scripts([RemoteScriptSummary])
    // iPhone → Mac
    case hello(version: Int, deviceID: UUID, proof: Data)
    case pairRequest(version: Int, deviceName: String, publicKey: Data, proof: Data)
    case command(RemoteCommand)
}

enum RemoteFrameError: Error { case tooLarge }

/// 4-byte big-endian length prefix followed by a JSON body.
enum RemoteFrame {
    static func encode(_ message: RemoteMessage) throws -> Data {
        let body = try JSONEncoder().encode(message)
        let length = UInt32(body.count)
        return Data([UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)]) + body
    }

    static func decode(_ body: Data) -> RemoteMessage? {
        // Unknown cases from a newer peer are skipped instead of dropping the link.
        try? JSONDecoder().decode(RemoteMessage.self, from: body)
    }
}

struct RemoteFrameDecoder {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length <= RemoteProtocol.maxFrameLength else { buffer = Data(); throw RemoteFrameError.tooLarge }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return frames
    }
}

/// Coalesces high-frequency drag deltas into at most ~30 nudges per second.
struct RemoteScrollAccumulator {
    var interval = 1.0 / 30
    var factor = 2.0
    private var pending = 0.0
    private var lastSent = -Double.infinity

    /// `fingerDelta` is the vertical finger movement; moving up advances the text.
    mutating func add(_ fingerDelta: Double, at time: Double) -> Double? {
        pending -= fingerDelta * factor
        return flush(at: time)
    }

    mutating func flush(at time: Double, force: Bool = false) -> Double? {
        guard abs(pending) >= 0.5, force || time - lastSent >= interval else { return nil }
        let points = min(RemoteProtocol.nudgeLimit, max(-RemoteProtocol.nudgeLimit, pending))
        pending = 0; lastSent = time
        return points
    }
}
