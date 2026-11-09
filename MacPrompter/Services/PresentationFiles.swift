import AppKit
import PDFKit

enum PresentationError: LocalizedError {
    case unreadable, empty
    var errorDescription: String? {
        switch self {
        case .unreadable: "Die PDF konnte nicht gelesen werden."
        case .empty: "Die PDF enthält keine Seiten."
        }
    }
}

/// Owns the library copies of linked PDFs and their security-scoped
/// bookmarks. PDF parsing runs off the main actor; documents and thumbnails
/// for display are cached on it.
@MainActor
final class PresentationFiles {
    struct Snapshot: Sendable {
        let pages: [SlidePage]
        let data: Data
        let modifiedAt: Date?
        let size: Int?
    }

    let folder: URL
    private var documents: [UUID: PDFDocument] = [:]
    private var thumbnails: [String: NSImage] = [:]

    init(folder: URL) { self.folder = folder }

    func storedURL(for deck: PresentationDeck) -> URL { folder.appending(path: "\(deck.id.uuidString).pdf") }

    func makeDeck(from url: URL, text: String = "") async throws -> PresentationDeck {
        let snapshot = try await Self.read(url)
        var deck = PresentationDeck(fileName: url.lastPathComponent, pages: snapshot.pages, text: text)
        try store(snapshot, for: &deck, original: url)
        return deck
    }

    /// Reads the original file when it changed since the last import.
    /// Returns nil when nothing changed or the original is unreachable; the
    /// library copy then stays in use.
    func changedSnapshot(of deck: PresentationDeck, force: Bool = false) async throws -> (snapshot: Snapshot, url: URL)? {
        guard let bookmark = deck.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard force || stale || values?.contentModificationDate != deck.fileModifiedAt || values?.fileSize != deck.fileSize else { return nil }
        return (try await Self.read(url), url)
    }

    /// Synchronous so it always applies to the deck's latest text edits.
    func apply(_ snapshot: Snapshot, from url: URL, to deck: inout PresentationDeck) throws -> PresentationChange {
        var updated = deck
        let change = updated.adopt(pages: snapshot.pages)
        updated.fileName = url.lastPathComponent
        try store(snapshot, for: &updated, original: url)
        deck = updated
        return change
    }

    /// Stores the PDF of an imported script file as the deck's library copy.
    func write(_ data: Data, for deck: PresentationDeck) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: storedURL(for: deck), options: .atomic)
        documents[deck.id] = nil
    }

    func duplicate(_ deck: PresentationDeck) -> PresentationDeck? {
        var copy = deck
        copy.id = UUID()
        do { try FileManager.default.copyItem(at: storedURL(for: deck), to: storedURL(for: copy)) } catch { return nil }
        return copy
    }

    func remove(_ deck: PresentationDeck) {
        documents[deck.id] = nil
        try? FileManager.default.removeItem(at: storedURL(for: deck))
    }

    func document(for deck: PresentationDeck) -> PDFDocument? {
        if let cached = documents[deck.id], cached.pageCount == deck.pages.count { return cached }
        guard let document = PDFDocument(url: storedURL(for: deck)), document.pageCount == deck.pages.count else { return nil }
        documents[deck.id] = document
        return document
    }

    func thumbnail(_ deck: PresentationDeck, page index: Int, width: CGFloat) -> NSImage? {
        guard deck.pages.indices.contains(index) else { return nil }
        let key = "\(deck.id)-\(deck.pages[index].id)-\(deck.fileModifiedAt?.timeIntervalSince1970 ?? 0)-\(Int(width))"
        if let cached = thumbnails[key] { return cached }
        guard let page = document(for: deck)?.page(at: index) else { return nil }
        let box = page.bounds(for: .cropBox)
        let height = box.width > 0 ? width * box.height / box.width : width * 0.5625
        let image = page.thumbnail(of: NSSize(width: width * 2, height: height * 2), for: .cropBox)
        thumbnails[key] = image
        return image
    }

    private func store(_ snapshot: Snapshot, for deck: inout PresentationDeck, original: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try snapshot.data.write(to: storedURL(for: deck), options: .atomic)
        deck.fileModifiedAt = snapshot.modifiedAt
        deck.fileSize = snapshot.size
        let access = original.startAccessingSecurityScopedResource()
        defer { if access { original.stopAccessingSecurityScopedResource() } }
        deck.bookmark = (try? original.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? deck.bookmark
        documents[deck.id] = nil
        thumbnails = thumbnails.filter { !$0.key.hasPrefix(deck.id.uuidString) }
    }

    nonisolated static func read(_ url: URL) async throws -> Snapshot {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let data = try Data(contentsOf: url)
        let pages = try await Task.detached(priority: .userInitiated) { try fingerprints(of: data) }.value
        return Snapshot(pages: pages, data: data, modifiedAt: values?.contentModificationDate, size: values?.fileSize)
    }

    nonisolated static func fingerprints(of data: Data) throws -> [SlidePage] {
        guard let document = PDFDocument(data: data) else { throw PresentationError.unreadable }
        guard document.pageCount > 0 else { throw PresentationError.empty }
        return (0..<document.pageCount).compactMap { document.page(at: $0).map(fingerprint) }
    }

    nonisolated static func fingerprint(_ page: PDFPage) -> SlidePage {
        let words = ScriptParser.normalize(page.string ?? "").split(whereSeparator: \.isWhitespace)
        return SlidePage(text: String(words.joined(separator: " ").prefix(600)), imageHash: differenceHash(page))
    }

    /// 64-bit difference hash of a small grayscale render. Survives re-export
    /// and small edits, separates pages without text.
    nonisolated static func differenceHash(_ page: PDFPage) -> UInt64 {
        let width = 36, height = 32
        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return 0 }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        page.draw(with: .cropBox, to: context)
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        func cell(_ x: Int, _ y: Int) -> Int {
            var sum = 0
            for dy in 0..<4 { for dx in 0..<4 { sum += Int(pixels[(y * 4 + dy) * width + x * 4 + dx]) } }
            return sum
        }
        var hash: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { hash = hash << 1 | (cell(x, y) < cell(x + 1, y) ? 1 : 0) } }
        return hash
    }
}
