import Foundation
import UniformTypeIdentifiers

/// The settings of the side pane that belong to a script. Screen choices,
/// mirroring and the countdown depend on the Mac and stay global.
struct ScriptSettings: Codable, Equatable, Sendable {
    var mode = PlaybackMode.automatic
    var speed = 36.0
    var font = ReadingFont.system
    var textColor = ReadingColor.white
    var fontSize = 28.0
    var lineSpacing = 12.0
    var focusLine = true
    var prompterOpacity = 1.0
    var docked = true
    var width = 620.0
    var height = 300.0
    var presenterView = true

    init() { }

    /// Tolerant: missing or unknown values (older or newer files) fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScriptSettings()
        mode = (try? c.decodeIfPresent(PlaybackMode.self, forKey: .mode)) ?? d.mode
        speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? d.speed
        font = (try? c.decodeIfPresent(ReadingFont.self, forKey: .font)) ?? d.font
        textColor = (try? c.decodeIfPresent(ReadingColor.self, forKey: .textColor)) ?? d.textColor
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? d.fontSize
        lineSpacing = (try? c.decodeIfPresent(Double.self, forKey: .lineSpacing)) ?? d.lineSpacing
        focusLine = (try? c.decodeIfPresent(Bool.self, forKey: .focusLine)) ?? d.focusLine
        prompterOpacity = (try? c.decodeIfPresent(Double.self, forKey: .prompterOpacity)) ?? d.prompterOpacity
        docked = (try? c.decodeIfPresent(Bool.self, forKey: .docked)) ?? d.docked
        width = (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? d.width
        height = (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? d.height
        presenterView = (try? c.decodeIfPresent(Bool.self, forKey: .presenterView)) ?? d.presenterView
    }

    /// Keeps values from files within the ranges the app supports.
    var clamped: ScriptSettings {
        var s = self
        s.speed = min(120, max(10, speed.isFinite ? speed : 36))
        s.fontSize = min(56, max(18, fontSize.isFinite ? fontSize : 28))
        s.lineSpacing = min(28, max(4, lineSpacing.isFinite ? lineSpacing : 12))
        s.prompterOpacity = min(1, max(0.2, prompterOpacity.isFinite ? prompterOpacity : 1))
        s.width = min(Preferences.widthRange.upperBound, max(Preferences.widthRange.lowerBound, width.isFinite ? width : 620))
        s.height = min(Preferences.heightRange.upperBound, max(Preferences.heightRange.lowerBound, height.isFinite ? height : 300))
        return s
    }
}

extension Preferences {
    var scriptSettings: ScriptSettings {
        get {
            var s = ScriptSettings()
            s.mode = mode; s.speed = speed; s.font = font; s.textColor = textColor; s.fontSize = fontSize; s.lineSpacing = lineSpacing
            s.focusLine = focusLine; s.prompterOpacity = prompterOpacity; s.docked = docked
            s.width = width; s.height = height; s.presenterView = presenterView
            return s
        }
        set {
            let s = newValue.clamped
            mode = s.mode; speed = s.speed; font = s.font; textColor = s.textColor; fontSize = s.fontSize; lineSpacing = s.lineSpacing
            focusLine = s.focusLine; prompterOpacity = s.prompterOpacity; docked = s.docked
            width = s.width; height = s.height; presenterView = s.presenterView
        }
    }
}

extension UTType {
    /// A self-contained script file: text, slides with the PDF, and script settings.
    static let macprompterScript = UTType(exportedAs: "io.github.fng-2002.macprompter.script", conformingTo: .data)
}

enum ScriptDocumentError: LocalizedError, Equatable {
    case notAScript, newerVersion(Int), missingPDF
    var errorDescription: String? {
        switch self {
        case .notAScript: "Die Datei ist keine macprompter-Skriptdatei."
        case .newerVersion(let version): "Die Datei stammt aus einer neueren macprompter-Version (Format \(version)). Bitte macprompter aktualisieren."
        case .missingPDF: "Die Präsentation in der Datei enthält keine PDF."
        }
    }
}

/// `.macprompter` file: one JSON document, so it can be mailed, AirDropped or
/// backed up as a single file. The PDF is embedded; bookmarks to the sender's
/// files are never included.
struct ScriptDocument: Codable, Equatable, Sendable {
    static let fileExtension = "macprompter"
    static let formatName = "macprompter.script"
    static let currentVersion = 1

    var format = ScriptDocument.formatName
    var version = ScriptDocument.currentVersion
    var exportedAt = Date()
    var script: Script
    var pdf: Data?

    init(script: Script, settings: ScriptSettings, pdf: Data?) {
        var script = script
        script.settings = settings
        script.presentation?.bookmark = nil
        self.script = script
        self.pdf = script.presentation == nil ? nil : pdf
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ScriptDocument {
        struct Header: Decodable { var format: String?; var version: Int? }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName else { throw ScriptDocumentError.notAScript }
        if let version = header.version, version > currentVersion { throw ScriptDocumentError.newerVersion(version) }
        do {
            let document = try decoder.decode(ScriptDocument.self, from: data)
            if document.script.presentation != nil && document.pdf == nil { throw ScriptDocumentError.missingPDF }
            return document
        } catch let error as ScriptDocumentError { throw error } catch { throw ScriptDocumentError.notAScript }
    }

    /// File name without characters that Finder or mail clients reject.
    static func fileName(for title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Skript" : String(cleaned.prefix(120))) + "." + fileExtension
    }
}
