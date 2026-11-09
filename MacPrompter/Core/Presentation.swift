import Foundation

/// One PDF page as remembered between PDF versions. The fingerprint (text and
/// a coarse image hash) lets a re-exported PDF keep its text assignments even
/// when pages are inserted, removed or reordered.
struct SlidePage: Codable, Equatable, Identifiable, Sendable {
    enum Flag: String, Codable, Sendable { case added, changed }
    var id = UUID()
    var text: String
    var imageHash: UInt64
    var flag: Flag?
}

/// Text spoken while one page, or a group of consecutive pages, is shown.
struct SlideSection: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var pageIDs: [UUID]
    var text = ""
}

struct PresentationDeck: Codable, Equatable, Sendable {
    var id = UUID()
    var fileName: String
    /// Security-scoped bookmark to the original file; a copy in the library is the fallback.
    var bookmark: Data?
    var fileModifiedAt: Date?
    var fileSize: Int?
    /// Pages in current PDF order.
    var pages: [SlidePage]
    /// Sections in reading order.
    var sections: [SlideSection]

    init(fileName: String, pages: [SlidePage], text: String = "") {
        self.fileName = fileName
        self.pages = pages
        sections = pages.map { SlideSection(pageIDs: [$0.id]) }
        if !sections.isEmpty { sections[0].text = text }
    }

    func pageIndices(of section: SlideSection) -> [Int] {
        section.pageIDs.compactMap { id in pages.firstIndex { $0.id == id } }.sorted()
    }

    var hasFlags: Bool { pages.contains { $0.flag != nil } || sections.contains { $0.pageIDs.isEmpty } }

    mutating func clearFlags() {
        for index in pages.indices { pages[index].flag = nil }
    }

    mutating func setText(_ text: String, section id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].text = text
    }

    /// Joins a section with the following one; pages and text are kept.
    mutating func groupWithNext(_ id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }), index + 1 < sections.count else { return }
        let next = sections.remove(at: index + 1)
        sections[index].pageIDs += next.pageIDs
        sections[index].text = [sections[index].text, next.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        sections[index].pageIDs = pageIndices(of: sections[index]).map { pages[$0].id }
    }

    /// Gives every page of a group its own section. The text stays with the first page.
    mutating func ungroup(_ id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }), sections[index].pageIDs.count > 1 else { return }
        let ordered = pageIndices(of: sections[index]).map { pages[$0].id }
        sections[index].pageIDs = [ordered[0]]
        sections.insert(contentsOf: ordered.dropFirst().map { SlideSection(pageIDs: [$0]) }, at: index + 1)
    }

    /// Only sections whose pages were removed from the PDF can be deleted, so
    /// every page always keeps a section.
    mutating func removeOrphan(_ id: UUID) {
        sections.removeAll { $0.id == id && $0.pageIDs.isEmpty }
    }

    var plainText: String {
        sections.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct PresentationChange: Equatable, Sendable {
    var added = 0, removed = 0, changed = 0
    var isEmpty: Bool { added == 0 && removed == 0 && changed == 0 }
    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append(added == 1 ? "1 neue Folie" : "\(added) neue Folien") }
        if changed > 0 { parts.append(changed == 1 ? "1 geänderte Folie" : "\(changed) geänderte Folien") }
        if removed > 0 { parts.append(removed == 1 ? "1 entfernte Folie" : "\(removed) entfernte Folien") }
        return parts.isEmpty ? "Keine inhaltlichen Änderungen" : parts.joined(separator: ", ")
    }
}

/// `current`/`count` are PDF pages, the unit of navigation. A slide is what
/// the audience perceives: one section, possibly revealed in several steps.
struct SlideStatus: Equatable, Sendable {
    var current: Int
    var count: Int
    var slide = 0, slideCount = 0, step = 0, steps = 1

    init(current: Int, count: Int, position: SlidePosition? = nil, slideCount: Int = 0) {
        self.current = current; self.count = count
        if let position, slideCount > 0 {
            slide = position.slide; step = position.step; steps = position.steps; self.slideCount = slideCount
        } else {
            slide = current; self.slideCount = count
        }
    }

    var label: String { SlideStatus.label(slide: slide, slideCount: slideCount, step: step, steps: steps) }

    static func label(slide: Int, slideCount: Int, step: Int, steps: Int) -> String {
        steps > 1 ? "Folie \(slide + 1) von \(slideCount) · Schritt \(step + 1)/\(steps)" : "Folie \(slide + 1) von \(slideCount)"
    }
}

struct SlidePosition: Equatable, Sendable {
    let slide: Int, step: Int, steps: Int
}

// MARK: - Script text and slide timeline

struct SlideCue: Equatable, Sendable {
    /// Reading this character (or beyond) shows `page`.
    let location: Int
    /// Where the prompter jumps when the page is selected manually.
    let anchor: Int
    let page: Int
}

struct SlideTimeline: Equatable, Sendable {
    let cues: [SlideCue]
    let pageCount: Int
    /// Slide and reveal step for every page; nil for pages without a section.
    var positions: [SlidePosition?] = []
    var slideCount = 0

    func page(at character: Int) -> Int? {
        guard let first = cues.first else { return nil }
        var low = 0, high = cues.count - 1, result = first.page
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].location <= character { result = cues[mid].page; low = mid + 1 } else { high = mid - 1 }
        }
        return result
    }

    func anchor(forPage page: Int) -> Int? { cues.first { $0.page == page }?.anchor }
}

enum PresentationComposer {
    static let nextMarker = "[Nächste Folie]"
    static let endMarker = "[Ende der Präsentation]"
    /// Cues inside a group's text that advance to its next page.
    static let advanceCues: Set<String> = ["weiter", "klick", "next", "click"]

    /// Slides are numbered by section, so a slide revealed in several PDF
    /// pages (builds) keeps one number.
    static func startMarker(slide: Int?, steps: Int) -> String {
        guard let slide else { return "[Ohne Folie]" }
        return steps > 1 ? "[Start · Folie \(slide + 1) · \(steps) Schritte]" : "[Start · Folie \(slide + 1)]"
    }

    /// The prompter reads a derived script: every section starts with a start
    /// cue and ends with "Nächste Folie". Cues never count as spoken words.
    static func compose(_ deck: PresentationDeck) -> (body: String, timeline: SlideTimeline) {
        var body = ""
        var length = 0
        var cues: [SlideCue] = []
        var boundary = 0
        func append(_ string: String) { body += string; length += (string as NSString).length }
        var positions = [SlidePosition?](repeating: nil, count: deck.pages.count)
        var slides = 0
        for (index, section) in deck.sections.enumerated() {
            let pages = deck.pageIndices(of: section)
            if index > 0 { append("\n\n") }
            let blockStart = length
            append(startMarker(slide: pages.isEmpty ? nil : slides, steps: pages.count) + "\n")
            for (step, page) in pages.enumerated() { positions[page] = SlidePosition(slide: slides, step: step, steps: pages.count) }
            if !pages.isEmpty { slides += 1 }
            let textStart = length
            let text = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
            append(text)
            if let first = pages.first {
                cues.append(SlideCue(location: index == 0 ? 0 : boundary, anchor: blockStart, page: first))
                cues += innerCues(text: text, offset: textStart, pages: Array(pages.dropFirst()))
            }
            if !text.isEmpty { append("\n") }
            boundary = length
            append(index == deck.sections.count - 1 ? endMarker : nextMarker)
        }
        return (body, SlideTimeline(cues: cues, pageCount: deck.pages.count, positions: positions, slideCount: slides))
    }

    private static func innerCues(text: String, offset: Int, pages: [Int]) -> [SlideCue] {
        guard !pages.isEmpty else { return [] }
        let ns = text as NSString
        let markers = ScriptParser.cueRanges(in: text).filter {
            advanceCues.contains(ScriptParser.normalize(ns.substring(with: NSRange(location: $0.location + 1, length: $0.length - 2)))
                .trimmingCharacters(in: .whitespaces))
        }
        if !markers.isEmpty {
            return zip(markers, pages).map { SlideCue(location: offset + $0.location, anchor: offset + $0.location, page: $1) }
        }
        // Without explicit cues a group advances evenly by spoken words.
        let words = ScriptParser.words(in: text)
        guard !words.isEmpty else { return [] }
        let count = pages.count + 1
        return pages.enumerated().compactMap { step, page in
            let word = (step + 1) * words.count / count
            guard word > 0, word < words.count else { return nil }
            let location = offset + words[word].range.location
            return SlideCue(location: location, anchor: location, page: page)
        }
    }
}

// MARK: - Matching a new PDF version

enum SlideMatcher {
    static let threshold = 0.5
    static let movedThreshold = 0.8

    static func words(_ text: String) -> Set<Substring> { Set(text.split(separator: " ")) }

    static func similarity(_ a: SlidePage, _ b: SlidePage) -> Double {
        similarity(a, words(a.text), b, words(b.text))
    }

    private static func similarity(_ a: SlidePage, _ aw: Set<Substring>, _ b: SlidePage, _ bw: Set<Substring>) -> Double {
        // dHash distances of a re-export stay small; unrelated pages land near 32.
        let image = max(0, 1 - Double((a.imageHash ^ b.imageHash).nonzeroBitCount) / 16)
        if aw.isEmpty && bw.isEmpty { return image }
        if aw.isEmpty || bw.isEmpty { return 0.3 * image }
        let text = a.text == b.text ? 1 : Double(aw.intersection(bw).count) / Double(aw.union(bw).count)
        return 0.75 * text + 0.25 * image
    }

    /// Order-preserving alignment that maximizes total similarity. Returns,
    /// for every new page, the index of the old page it continues (if any) and
    /// whether that pairing is a positional guess for an edited page.
    static func align(old: [SlidePage], new: [SlidePage]) -> [(old: Int, edited: Bool)?] {
        let n = old.count, m = new.count
        let oldWords = old.map { words($0.text) }, newWords = new.map { words($0.text) }
        var score = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        var sim = Array(repeating: Array(repeating: 0.0, count: m), count: n)
        for i in 0..<n { for j in 0..<m { sim[i][j] = similarity(old[i], oldWords[i], new[j], newWords[j]) } }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                var best = max(score[i + 1][j], score[i][j + 1])
                if sim[i][j] >= threshold { best = max(best, sim[i][j] + score[i + 1][j + 1]) }
                score[i][j] = best
            }
        }
        var result: [(old: Int, edited: Bool)?] = Array(repeating: nil, count: m)
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if sim[i][j] >= threshold, abs(score[i][j] - (sim[i][j] + score[i + 1][j + 1])) < 1e-9 {
                result[j] = (i, false); pairs.append((i, j)); i += 1; j += 1
            } else if score[i + 1][j] >= score[i][j + 1] { i += 1 } else { j += 1 }
        }
        // Moved pages: near-identical content anywhere else in the file.
        var usedOld = Set(pairs.map(\.0))
        let moves = (0..<m).filter { result[$0] == nil }.flatMap { j in
            (0..<n).filter { !usedOld.contains($0) && sim[$0][j] >= movedThreshold }.map { (old: $0, new: j, sim: sim[$0][j]) }
        }.sorted { $0.sim > $1.sim }
        for move in moves where result[move.new] == nil && !usedOld.contains(move.old) {
            result[move.new] = (move.old, false); usedOld.insert(move.old)
        }
        // Between two confident matches, the same number of unmatched old and
        // new pages are most likely edited versions of each other.
        var previous = (-1, -1)
        for next in pairs + [(n, m)] {
            let oldGap = ((previous.0 + 1)..<next.0).filter { !usedOld.contains($0) }
            let newGap = ((previous.1 + 1)..<next.1).filter { result[$0] == nil }
            if !oldGap.isEmpty, oldGap.count == newGap.count {
                for (o, p) in zip(oldGap, newGap) { result[p] = (o, true) }
            }
            previous = next
        }
        return result
    }
}

extension PresentationDeck {
    /// Adopts the pages of a new PDF version. Matched pages keep their IDs and
    /// therefore their text; new pages join the group they were inserted into
    /// or get an empty section; text of removed pages is never discarded.
    @discardableResult
    mutating func adopt(pages newPages: [SlidePage]) -> PresentationChange {
        let mapping = SlideMatcher.align(old: pages, new: newPages)
        var change = PresentationChange()
        var adopted = newPages
        for (index, match) in mapping.enumerated() {
            if let match {
                adopted[index].id = pages[match.old].id
                adopted[index].flag = match.edited ? .changed : pages[match.old].flag
                if match.edited { change.changed += 1 }
            } else {
                adopted[index].flag = .added
                change.added += 1
            }
        }
        let kept = Set(adopted.map(\.id))
        change.removed = pages.filter { !kept.contains($0.id) }.count
        let position = Dictionary(uniqueKeysWithValues: adopted.enumerated().map { ($1.id, $0) })
        var sectionOf: [UUID: Int] = [:]
        for (index, section) in sections.enumerated() {
            sections[index].pageIDs = section.pageIDs.filter { kept.contains($0) }
            for id in sections[index].pageIDs { sectionOf[id] = index }
        }
        var newSections: [(key: Double, section: SlideSection)] = []
        var run: [Int] = []
        func flushRun(before next: Int) {
            guard !run.isEmpty else { return }
            let before = run[0] > 0 ? sectionOf[adopted[run[0] - 1].id] : nil
            let after = next < adopted.count ? sectionOf[adopted[next].id] : nil
            if let before, before == after {
                sections[before].pageIDs += run.map { adopted[$0].id }
            } else {
                newSections += run.map { (Double($0), SlideSection(pageIDs: [adopted[$0].id])) }
            }
            run = []
        }
        for index in adopted.indices {
            if mapping[index] == nil { run.append(index) } else { flushRun(before: index) }
        }
        flushRun(before: adopted.count)
        // Sections follow the PDF order; sections without pages stay behind
        // the section they followed before.
        var keyed: [(key: Double, order: Int, section: SlideSection)] = []
        var lastKey = -1.0
        for (order, var section) in sections.enumerated() {
            section.pageIDs.sort { position[$0, default: 0] < position[$1, default: 0] }
            if let first = section.pageIDs.first, let index = position[first] { lastKey = Double(index) }
            keyed.append((section.pageIDs.isEmpty ? lastKey + 0.5 : lastKey, order, section))
        }
        keyed += newSections.map { ($0.key, Int.max, $0.section) }
        sections = keyed.sorted { ($0.key, $0.order) < ($1.key, $1.order) }.map(\.section)
        pages = adopted
        return change
    }
}
