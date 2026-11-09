import Foundation

struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var modifiedAt = Date()
    var language: SpeechLanguage = .german
    /// Optional, so libraries written before PDF support still decode. When
    /// set, `body` is derived from the deck's sections.
    var presentation: PresentationDeck?
    /// Side-pane settings remembered for this script; nil until first changed.
    var settings: ScriptSettings?

    static let welcome = Script(title: "Dein erster Take", body: """
    Willkommen bei macprompter.

    [Lächeln]
    Gute Geschichten beginnen nicht mit perfekten Worten. Sie beginnen mit einem Gedanken, den wir teilen möchten.

    Schau in die Kamera. Atme einmal durch. Und erzähl deine Geschichte in deinem eigenen Tempo.

    [Pause]
    Du musst dir nicht jeden Satz merken. Dein Text bleibt direkt bei der Kamera, damit du bei deinem Publikum bleiben kannst.

    Im Sprachmodus folgt macprompter deinen Worten. Wenn du innehältst, bleibt auch dein Text stehen.

    [Langsamer]
    Fahre mit der Maus über den Prompter, um kurz zu pausieren. Nimm dir die Zeit, die du brauchst.

    Bereit? Dann gehört dieser Moment dir.
    """)
    static let english = Script(title: "A little introduction", body: """
    Hello, and welcome.

    [Smile]
    Today I want to share a simple idea: the best way to connect with people is to be yourself.

    You don't need a perfect script. You need a clear thought, a little courage, and a moment to breathe.

    [Pause]
    Look into the camera. Take your time. Let's begin.
    """, language: .english)
}

enum PlaybackMode: String, Codable, CaseIterable, Identifiable {
    case voice, automatic, manual
    var id: Self { self }
    var title: String {
        switch self { case .voice: "Stimme"; case .automatic: "Automatisch"; case .manual: "Manuell" }
    }
    var symbol: String {
        switch self { case .voice: "waveform"; case .automatic: "forward.frame"; case .manual: "keyboard" }
    }
}

/// A single gate used by timers, speech results, keys and the scroll wheel.
struct PlaybackGate {
    var isVisible = false
    var isPlaying = false
    var isHovering = false
    var countdown = 0
    var allowsMovement: Bool { isVisible && !isHovering && countdown == 0 }
    var allowsAutomaticMovement: Bool { allowsMovement && isPlaying }
    /// The scroll wheel is a deliberate gesture and the only way to move the
    /// text with the pointer on the prompter; hover keeps everything else frozen.
    var allowsScrolling: Bool { isVisible && countdown == 0 }
}
