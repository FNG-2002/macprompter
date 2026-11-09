import Foundation

/// Compare prepared passage lookup with the previous per-request parser.
/// Compile with ScriptText.swift, ScriptFollower.swift, LexicalBridge.swift and
/// SemanticRecovery.swift.
@main
struct RenderingBenchmark {
    static func main() {
        let body = (0..<200).map { "Abschnitt \($0) behandelt Solarmodule und moderne Speicher für unsere gemeinsame Zukunft." }.joined(separator: " ")
        let index = SemanticScriptIndex(text: body)
        var before: [Double] = [], after: [Double] = []
        for i in 0..<100 {
            let position = (i * 19) % 2100
            let start = ProcessInfo.processInfo.systemUptime
            let original = legacyWindows(text: body, nextIndex: position)
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let ready = ProcessInfo.processInfo.systemUptime
            let prepared = index.windows(nextIndex: position)
            after.append((ProcessInfo.processInfo.systemUptime - ready) * 1000)
            precondition(original.map(\.text) == prepared.map(\.text))
            precondition(original.map(\.startIndex) == prepared.map(\.startIndex))
        }
        before.sort(); after.sort()
        print("PASSAGES 2200 words: old median=\(before[50]) p95=\(before[94]) ms; prepared median=\(after[50]) p95=\(after[94]) ms")
        for distance in [40.0, 300, 600] {
            func elapsed(new: Bool) -> Double {
                var position = 0.0, time = 0.0
                let dt = 1.0 / 120
                while position < distance * 0.95 && time < 5 {
                    if new { position = ReadingMotion.advance(from: position, to: distance, dt: dt, reducedMotion: false) }
                    else { position += min(2200 * dt, (distance - position) * (1 - exp(-dt / 0.18))) }
                    time += dt
                }
                return time * 1000
            }
            print("MOTION 95% of \(distance) pt: old=\(elapsed(new: false)) new=\(elapsed(new: true)) ms (simulation)")
        }
    }
    static func legacyWindows(text: String, nextIndex: Int) -> [SemanticWindow] {
        let tokens = ScriptParser.words(in: text)
        guard nextIndex < tokens.count else { return [] }
        let end = min(tokens.count, nextIndex + 24)
        let ns = text as NSString
        var starts = [nextIndex]
        for i in (nextIndex + 1)..<end {
            let gap = ns.substring(with: NSRange(location: NSMaxRange(tokens[i - 1].range), length: tokens[i].range.location - NSMaxRange(tokens[i - 1].range)))
            if gap.contains(where: { ".!?\n".contains($0) }) { starts.append(i) }
        }
        starts += [nextIndex + 4, nextIndex + 8]
        var seen: Set<Int> = []
        return starts.filter { $0 < end && seen.insert($0).inserted }.prefix(4).compactMap { start in
            var stop = min(end, start + 12)
            if start + 4 < stop {
                for i in (start + 4)..<stop {
                    let gap = ns.substring(with: NSRange(location: NSMaxRange(tokens[i - 1].range), length: tokens[i].range.location - NSMaxRange(tokens[i - 1].range)))
                    if gap.contains(where: { ".!?\n".contains($0) }) { stop = i; break }
                }
            }
            guard stop - start >= 4 else { return nil }
            let slice = tokens[start..<stop]
            return SemanticWindow(text: slice.map { ns.substring(with: $0.range) }.joined(separator: " "),
                words: slice.map(\.normalized), startIndex: start)
        }
    }

}
