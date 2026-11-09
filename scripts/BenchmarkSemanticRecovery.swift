import Foundation

/// Compile with -O alongside Core/ScriptText.swift, Core/ScriptFollower.swift,
/// Core/LexicalBridge.swift and Services/SemanticRecovery.swift. Measures model
/// work, not microphone latency.
@main
struct SemanticBenchmark {
    static func main() async {
        let engine = AppleSemanticRecovery()
        let cases: [(String, SpeechLanguage, String, String, String)] = [
            ("plain", .german, "Anschließend vergleichen wir die Kosten und prüfen die Ergebnisse.",
             "Nun kontrollieren wir die Ergebnisse", "Eine völlig andere Geschichte über Ergebnisse"),
            ("plain", .english, "Next we compare the costs and examine the results.",
             "Now let's verify our results", "I dreamed about completely different results"),
            ("return", .german, "Anschließend vergleichen wir die Kosten und prüfen sämtliche Ergebnisse.",
             "Urlaub gab es eine lustige Überraschung Jetzt überprüfen wir die Ergebnisse",
             "Das erinnert mich an meinen Urlaub eine andere Geschichte über Ergebnisse"),
            ("return", .english, "Next we compare the costs and examine the results.",
             "vacation had a rather surprising ending Now let's verify our results",
             "I remember my holidays and dreamed about completely different results")
        ]
        for (label, language, script, positive, negative) in cases {
            let windows = SemanticCandidates.windows(text: script, nextIndex: 0)
            let coldStart = ProcessInfo.processInfo.systemUptime
            let warmup = await engine.evaluate(SemanticRecoveryRequest(revision: 0, nextIndex: 0,
                language: language, heard: [], windows: windows))
            guard warmup.available else { print("\(language.rawValue): model unavailable"); continue }
            let cold = (ProcessInfo.processInfo.systemUptime - coldStart) * 1_000
            var timings: [Double] = []
            var accepted = 0
            var rejected = 0
            for i in 0..<100 {
                let spoken = i.isMultiple(of: 2) ? positive : negative
                let result = await engine.evaluate(SemanticRecoveryRequest(revision: UInt64(i + 1), nextIndex: 0,
                    language: language, heard: spoken.split(separator: " ").map(String.init), windows: windows))
                timings.append(result.milliseconds)
                if i.isMultiple(of: 2), result.wordIndex != nil { accepted += 1 }
                if !i.isMultiple(of: 2), result.wordIndex == nil { rejected += 1 }
            }
            timings.sort()
            print("\(label) \(language.rawValue): cold_ms=\(cold) warm_median_ms=\(timings[50]) warm_p95_ms=\(timings[94]) positives=\(accepted)/50 negatives=\(rejected)/50")
        }
    }
}
