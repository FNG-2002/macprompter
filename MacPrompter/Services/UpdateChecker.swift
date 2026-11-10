import Foundation
import Observation

/// Looks for a newer release once after launch and then daily while the app
/// runs, if the setting is on (default). Shows a notice; never installs.
@MainActor @Observable
final class UpdateChecker {
    private(set) var available: AvailableUpdate?
    private(set) var isChecking = false
    /// Result of the last check started by hand, for settings and the menu.
    private(set) var message: String?
    /// The notice was closed for this version; a newer one shows again.
    var dismissedVersion: String?
    var notice: AvailableUpdate? { available.flatMap { $0.version == dismissedVersion ? nil : $0 } }
    let currentVersion: String
    @ObservationIgnored var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        // Ephemeral: no cookies, no cache, nothing stored on disk.
        try await URLSession(configuration: .ephemeral).data(for: request)
    }
    @ObservationIgnored private var schedule: Task<Void, Never>?

    init(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.currentVersion = currentVersion
    }

    func setEnabled(_ enabled: Bool) {
        schedule?.cancel(); schedule = nil
        guard enabled else { available = nil; return }
        schedule = Task { [weak self] in
            // Not during launch; the library opens first.
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(UpdateCheck.interval))
            }
        }
    }

    func check(manual: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let (data, response) = try await fetch(UpdateCheck.request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            available = UpdateCheck.update(fromLatestRelease: data, current: currentVersion)
            if manual { dismissedVersion = nil }
            message = available.map { "Version \($0.version) ist verfügbar." } ?? "macprompter \(currentVersion) ist aktuell."
        } catch {
            // Offline or GitHub unreachable: silent in the background.
            if manual { message = "GitHub ist gerade nicht erreichbar. Versuche es später noch einmal." }
        }
    }
}
