import Foundation

/// A newer release on GitHub than the running version.
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let url: URL
}

/// Numeric release version such as "1.1.0" or tag "v1.1.0"; pre-release
/// suffixes are not compared, GitHub's latest release excludes them anyway.
struct AppVersion: Comparable, Sendable {
    let parts: [Int]
    init?(_ text: String) {
        let core = text.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }.prefix { $0 != "-" && $0 != "+" }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4, numbers.allSatisfy({ $0 != nil }) else { return nil }
        var parts = numbers.compactMap { $0 }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

/// Asks GitHub for the version number of the latest release (ADR-29). Only
/// the request itself leaves the Mac; nothing is downloaded or installed.
enum UpdateCheck {
    static let endpoint = URL(string: "https://api.github.com/repos/FNG-2002/macprompter/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60

    static var request: URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub requires a user agent; no version or device details.
        request.setValue("macprompter", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Nil when the release is not newer, a draft, a pre-release or unreadable.
    static func update(fromLatestRelease data: Data, current: String) -> AvailableUpdate? {
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              release.html_url.host() == "github.com",
              let latest = AppVersion(release.tag_name), let running = AppVersion(current), running < latest else { return nil }
        return AvailableUpdate(version: String(release.tag_name.drop { $0 == "v" || $0 == "V" }), url: release.html_url)
    }
}
