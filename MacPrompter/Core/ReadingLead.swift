import Foundation

/// Speech-paced scrolling (ADR-19), an option in voice mode. Between
/// recognized words the reading position keeps gliding at the speaking rate, at most
/// `maxLead` characters past the last confirmed word. It stops when no word
/// was confirmed for `stallAfter` seconds or the voice goes quiet, and it
/// never moves back by itself; only a re-acquired position resets it. The
/// highlight stays on recognized words. Callers supply time, so tests are
/// deterministic.
struct ReadingLead {
    /// About three to four words, well under half a typical line.
    static let maxLead = 24.0
    static let stallAfter = 0.9
    static let window = 3.0
    /// A longer gap is a pause, not part of the speaking rate.
    static let pauseGap = 1.5

    private struct Sample { let time: Double; let character: Double }
    private var samples: [Sample] = []
    private var confirmed: Double?
    private var confirmedAt = 0.0
    private(set) var estimate: Double?

    /// Characters per second over the last few seconds of continuous reading.
    var rate: Double? {
        guard let first = samples.first, let last = samples.last, last.time - first.time >= 0.6,
              last.character > first.character else { return nil }
        return min(40, (last.character - first.character) / (last.time - first.time))
    }

    /// `character` is where the next unspoken word starts.
    mutating func confirm(character: Double, at time: Double, jump: Bool) {
        if jump || confirmed.map({ character < $0 }) ?? false {
            samples = []; estimate = character
        }
        if let last = samples.last, time - last.time > Self.pauseGap { samples = [] }
        samples.append(Sample(time: time, character: character))
        samples.removeAll { time - $0.time > Self.window }
        confirmed = character; confirmedAt = time
        estimate = min(character + Self.maxLead, max(estimate ?? character, character))
    }

    mutating func advance(by dt: Double, now: Double, speaking: Bool) {
        guard dt > 0, speaking, let confirmed, let current = estimate, let rate, now - confirmedAt < Self.stallAfter else { return }
        estimate = min(confirmed + Self.maxLead, current + rate * dt)
    }

    mutating func reset() { self = ReadingLead() }
}

/// Coarse voice activity from the input meter: a slowly adapting noise floor
/// and a short hold, enough to tell speaking from a pause between sentences.
struct VoiceActivity {
    static let hold = 0.25
    private var floor: Float = 0.05
    private var lastVoice = -Double.infinity

    mutating func observe(level: Float, at time: Double, dt: Double) -> Bool {
        if level < floor { floor = max(0.005, level) } else { floor += (level - floor) * Float(min(1, dt * 0.15)) }
        if level > max(0.12, floor * 3) { lastVoice = time }
        return time - lastVoice < Self.hold
    }
}
