import Foundation
import Observation

enum ReadingFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono, openDyslexic
    var id: Self { self }
    var title: String {
        switch self { case .system: "System"; case .rounded: "Rund"; case .serif: "Serif"; case .mono: "Mono"; case .openDyslexic: "Dyslexie" }
    }
}

/// Text colour of the prompter. Cues keep their own grey.
enum ReadingColor: String, Codable, CaseIterable, Identifiable {
    case white, yellow, green, blue, pink, orange
    var id: Self { self }
    var title: String {
        switch self { case .white: "Weiß"; case .yellow: "Gelb"; case .green: "Grün"; case .blue: "Blau"; case .pink: "Rosa"; case .orange: "Orange" }
    }
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: (1, 1, 1)
        case .yellow: (1, 0.86, 0.3)
        case .green: (0.45, 0.9, 0.55)
        case .blue: (0.5, 0.72, 1)
        case .pink: (1, 0.6, 0.75)
        case .orange: (1, 0.7, 0.35)
        }
    }
}

struct Preferences: Codable, Equatable {
    var mode: PlaybackMode = .automatic
    var font: ReadingFont = .system
    var fontSize = 28.0
    var lineSpacing = 12.0
    var speed = 36.0
    var width = 620.0
    var height = 300.0
    var countdownSeconds = 3
    var mirror = false
    var focusLine = true
    var docked = true
    var displayID: UInt32 = 0
    var floatingX: Double?
    var floatingY: Double?
    var reduceMotion = false
    // Optional storage preserves older preferences.v1 JSON without resetting
    // the user's fonts, display placement or other existing settings. Keys of
    // removed settings (semantic recovery, dictation: always on, ADR-22) are
    // ignored when decoding.
    private var speechPacedScroll: Bool?
    /// Voice mode: keep gliding at speaking pace between recognized words (ADR-19).
    var speechPacedScrolling: Bool {
        get { speechPacedScroll ?? false }
        set { speechPacedScroll = newValue }
    }
    private var predictiveWord: Bool?
    /// Voice mode moves the word highlight on at speaking pace, at most two
    /// words past the last recognized word. On unless switched off.
    var predictiveHighlight: Bool {
        get { predictiveWord ?? true }
        set { predictiveWord = newValue }
    }
    private var slidesDisplay: UInt32?
    private var presenterViewEnabled: Bool?
    /// Screen for the audience slides; 0 picks a screen other than the prompter's.
    var presentationDisplayID: UInt32 {
        get { slidesDisplay ?? 0 }
        set { slidesDisplay = newValue }
    }
    var presenterView: Bool {
        get { presenterViewEnabled ?? true }
        set { presenterViewEnabled = newValue }
    }
    private var backgroundOpacity: Double?
    /// Opacity of the prompter's black background; text always stays opaque.
    var prompterOpacity: Double {
        get { backgroundOpacity ?? 1 }
        set { backgroundOpacity = newValue }
    }
    private var agentAccessEnabled: Bool?
    private var agentPort: Int?
    /// MCP endpoint for AI agents on 127.0.0.1; off by default.
    var mcpEnabled: Bool {
        get { agentAccessEnabled ?? false }
        set { agentAccessEnabled = newValue }
    }
    var mcpPort: UInt16 {
        get { agentPort.flatMap { UInt16(exactly: $0) }.map { max(1024, $0) } ?? MCPServer.defaultPort }
        set { agentPort = Int(newValue) }
    }
    private var scrollAnywhere: Bool?
    /// The scroll wheel moves the prompter even when the pointer is elsewhere.
    var scrollWheelAnywhere: Bool {
        get { scrollAnywhere ?? true }
        set { scrollAnywhere = newValue }
    }
    private var slidesFollow: Bool?
    /// Slides change when the text passes a slide cue (voice, timer, scrolling).
    var slidesFollowReading: Bool {
        get { slidesFollow ?? true }
        set { slidesFollow = newValue }
    }
    private var readingColor: ReadingColor?
    var textColor: ReadingColor {
        get { readingColor ?? .white }
        set { readingColor = newValue }
    }
    private var remoteEnabled: Bool?
    var remoteControlEnabled: Bool {
        get { remoteEnabled ?? false }
        set { remoteEnabled = newValue }
    }
}

@MainActor @Observable
final class PreferenceStore {
    var value: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences.v1") }
        }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: "preferences.v1").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        value.fontSize = min(56, max(18, value.fontSize))
        value.width = min(Preferences.widthRange.upperBound, max(Preferences.widthRange.lowerBound, value.width))
        value.height = min(Preferences.heightRange.upperBound, max(Preferences.heightRange.lowerBound, value.height))
        value.speed = min(120, max(10, value.speed))
        value.countdownSeconds = min(10, max(0, value.countdownSeconds))
        value.prompterOpacity = min(1, max(0.2, value.prompterOpacity))
    }
}
