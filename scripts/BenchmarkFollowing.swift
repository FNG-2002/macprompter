import Foundation

/// Run with swiftc -O alongside Core/ScriptText.swift, Core/ScriptFollower.swift
/// and Core/LexicalBridge.swift.
@main
struct FollowingBenchmark {
    static func main() {
        let scenarios = [
            ("DE distinctive", "Heute untersuchen wir Solarmodule und moderne Speicher", "Heute untersuchen wir", "Das erinnert mich an eine ziemlich lange Geschichte aus meinem letzten Urlaub", "Solarmodule", 4),
            ("EN common then distinctive", "Welcome friends. The batteries store energy", "Welcome friends", "Let me tell a completely unrelated story", "the batteries", 4),
            ("DE clause", "Wir zeigen die wichtigsten Ergebnisse unserer Untersuchung", "Wir zeigen", "und das hat mich gestern wirklich sehr überrascht", "die wichtigsten", 4),
            ("EN clause", "Today we discuss the remarkable results of our experiment", "Today we discuss", "which was actually quite a surprise when I first saw it", "the remarkable", 5)
        ]
        for (label, script, prefix, aside, resumed, expected) in scenarios {
            var follower = ScriptFollower(text: script)
            _ = follower.consume(prefix, segment: 0, accepting: true)
            _ = follower.consume(aside, segment: 1, accepting: true)
            _ = follower.consume(resumed, segment: 2, accepting: true)
            print("\(label): next=\(follower.nextIndex) expected=\(expected)")
        }
        let text = (0..<200).map { "Abschnitt \($0) behandelt Solarmodule und moderne Speicher für unsere gemeinsame Zukunft." }.joined(separator: " ")
        var durations: [Double] = []
        for _ in 0..<30 {
            var follower = ScriptFollower(text: text)
            for (i, phrase) in ["Abschnitt", "Abschnitt null", "Abschnitt null behandelt Solarmodule", "Das erinnert mich an eine Geschichte aus dem Urlaub", "und moderne", "Speicher", "für unsere gemeinsame Zukunft", "unrelated question", "Zukunft"].enumerated() {
                let start = ProcessInfo.processInfo.systemUptime
                _ = follower.consume(phrase, segment: Double(i), accepting: true)
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)

            }
        }
        durations.sort()
        print("TRACKER samples=\(durations.count) p50_ms=\(durations[durations.count / 2]) p95_ms=\(durations[Int(Double(durations.count - 1) * 0.95)]) max_ms=\(durations.last!)")

        let flexibleCases = [
            ("EN changed", "Next we compare the costs and examine the results carefully.", "Then we look at costs and briefly examine", "examine"),
            ("DE changed", "Jetzt prüfen wir die Kosten unserer bisherigen Planung und die Ergebnisse.", "Wir betrachten Kosten der neuen Planung und Ergebnisse", "ergebnisse"),
            ("DE trailing", "Als Nächstes vergleichen wir die Kosten und prüfen die Ergebnisse.", "Die Kosten und prüfen würde ich sagen", "prufen"),
            ("DE cooking", "Im nächsten Schritt schneiden wir Tomaten und würzen die Soße.", "Danach kommen Tomaten hinein und würzen wir", "wurzen"),
            ("EN travel", "After the break we explore gardens and photograph historic buildings.", "Later we visit gardens then photograph some", "photograph")
        ]
        var returnTimes: [Double] = []
        var successfulReturns = 0
        for repetition in 0..<30 {
            for (label, body, spoken, expected) in flexibleCases {
                var follower = ScriptFollower(text: "Welcome everyone. " + body)
                _ = follower.consume("Welcome everyone", segment: 0, accepting: true)
                _ = follower.consume("That reminds me of an unrelated story from my vacation", segment: 1, accepting: true)
                let start = ProcessInfo.processInfo.systemUptime
                _ = follower.consume(spoken, segment: 2, accepting: true)
                returnTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                let actual = follower.lastMatch?.wordIndices.last.map { follower.tokens[$0].normalized }
                if actual == expected { successfulReturns += 1 }
                if repetition == 0 { print("FLEXIBLE \(label): \(actual ?? "waiting") expected=\(expected)") }
            }
        }
        returnTimes.sort()
        print("FLEXIBLE samples=\(returnTimes.count) matched=\(successfulReturns) p50_ms=\(returnTimes[returnTimes.count / 2]) p95_ms=\(returnTimes[Int(Double(returnTimes.count - 1) * 0.95)]) max_ms=\(returnTimes.last!)")

        // Recognizer spellings (measured with SpeechTranscriber) fed word by
        // word like growing volatile results. A stall is a heard word after
        // which the position did not advance.
        let spellingCases = [
            ("DE drei", "Wir planen 3 Schritte für morgen.", "Wir planen drei Schritte für morgen"),
            ("DE 25", "Wir sparen fünfundzwanzig Prozent der Kosten.", "Wir sparen 25 Prozent der Kosten"),
            ("EN 25%", "We save twenty-five percent of the cost.", "We save 25% of the cost"),
            ("DE % script", "Wir sparen 25 % der Kosten.", "Wir sparen 25 Prozent der Kosten"),
            ("EN 112", "We had one hundred twelve customers last year.", "We had 112 customers last year"),
            ("DE Dr.", "Heute schreibt Doktor Müller einen Brief.", "Heute schreibt Dr. Müller einen Brief"),
            ("DE z. B.", "Wir nutzen z. B. eine Wärmepumpe im Keller.", "Wir nutzen zum Beispiel eine Wärmepumpe im Keller"),
            ("DE compound", "Die Solar-Module liefern Strom.", "Die Solarmodule liefern Strom"),
            ("EN email", "Please send an e-mail today.", "Please send an email today"),
            ("EN don't", "We do not stop here today.", "We don't stop here today"),
            ("DE inflection", "Moderne Speicher liefern nachhaltige Energie.", "Moderne Speichern liefern nachhaltige Energie"),
            ("EN inflection", "The batteries store clean energy for tomorrow.", "The battery store clean energy for tomorrow")
        ]
        var stalls = 0, completed = 0
        for (label, body, spoken) in spellingCases {
            var follower = ScriptFollower(text: body)
            let words = spoken.split(separator: " ")
            var trace: [Int] = [], previous = 0
            for count in 1...words.count {
                _ = follower.consume(words[..<count].joined(separator: " "), segment: 0, accepting: true)
                if follower.nextIndex <= previous { stalls += 1 }
                previous = follower.nextIndex; trace.append(previous)
            }
            if follower.nextIndex == follower.tokens.count { completed += 1 }
            print("SPELLING \(label): \(trace.map(String.init).joined(separator: " ")) of \(follower.tokens.count)")
        }
        print("SPELLING cases=\(spellingCases.count) heard_words=\(spellingCases.map { $0.2.split(separator: " ").count }.reduce(0, +)) stalls=\(stalls) completed=\(completed)")

        // Fast results end in partial words while a word is still spoken.
        // A stall is a result with a new complete word but no progress.
        let fragmentStream = [
            ("Heute zeige ich euch wie", true), ("Heute zeige ich euch wie Moder", false), ("Heute zeige ich euch wie moderne Spei", true),
            ("Heute zeige ich euch wie moderne Speicher nach", true), ("Heute zeige ich euch wie moderne Speicher nachhaltige", true),
            ("Heute zeige ich euch wie moderne Speicher nachhaltige Energien lief", true),
            ("Heute zeige ich euch wie moderne Speicher nachhaltige Energie liefern", true),
            ("Heute zeige ich euch wie moderne Speicher nachhaltige Energie liefern und war", true),
            ("Heute zeige ich euch wie moderne Speicher nachhaltige Energie liefern und warum das", true)
        ]
        var fragmentFollower = ScriptFollower(text: "Heute zeige ich euch, wie moderne Speicher nachhaltige Energie liefern und warum das für unsere Zukunft wichtig ist.")
        var fragmentStalls = 0, expectedProgress = 0, previousIndex = 0
        for (text, completesWord) in fragmentStream {
            _ = fragmentFollower.consume(text, segment: 0, accepting: true)
            if completesWord { expectedProgress += 1; if fragmentFollower.nextIndex <= previousIndex { fragmentStalls += 1 } }
            previousIndex = fragmentFollower.nextIndex
        }
        print("FRAGMENT results_with_new_word=\(expectedProgress) stalls=\(fragmentStalls)")

    }
}
