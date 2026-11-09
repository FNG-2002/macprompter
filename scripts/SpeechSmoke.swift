// Runs local model transcription on a supplied fixture, without microphone access.
import Foundation
import AVFoundation
import Speech

@main struct SpeechSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: speech-smoke <de-DE|en-US> <audio-file>"); return
        }
        let language = CommandLine.arguments[1]
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            print("UNAVAILABLE \(language)"); return
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [module])
        print("MODEL \(language): \(status)")
        if status != .installed {
            guard CommandLine.arguments.contains("--install") else { print("SKIPPED: no model installed; start voice mode in the app to download."); return }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                print("INSTALLING \(language)")
                try await request.downloadAndInstall()
            }
        }
        let resultTask = Task {
            var transcript = ""
            for try await result in module.results { transcript += String(result.text.characters) + " " }
            return transcript
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]))
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let result = try await resultTask.value
        print("TRANSCRIPT: \(result)")
        guard !result.trimmingCharacters(in: .whitespaces).isEmpty else { throw NSError(domain: "SpeechSmoke", code: 1) }
    }
}
