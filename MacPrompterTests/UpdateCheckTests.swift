import XCTest
@testable import MacPrompter

final class UpdateCheckTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, url: String = "https://github.com/FNG-2002/macprompter/releases/tag/") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"assets":[]}"#.utf8)
    }

    func testVersionsCompareNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.0")), try XCTUnwrap(AppVersion("v1.10.0")))
        XCTAssertEqual(AppVersion("1.1"), AppVersion("v1.1.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.1.0")), try XCTUnwrap(AppVersion("1.1.1")))
        XCTAssertEqual(AppVersion("1.2.0-beta.1")?.parts, [1, 2])
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    func testOnlyANewerPublishedReleaseIsAnUpdate() {
        XCTAssertEqual(UpdateCheck.update(fromLatestRelease: release("v1.2.0"), current: "1.1.0"),
                       AvailableUpdate(version: "1.2.0", url: URL(string: "https://github.com/FNG-2002/macprompter/releases/tag/v1.2.0")!))
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: release("v1.1.0"), current: "1.1.0"))
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: release("v1.0.0"), current: "1.1.0"), "older release")
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: release("v2.0.0", draft: true), current: "1.1.0"))
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: release("v2.0.0", prerelease: true), current: "1.1.0"))
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: release("v2.0.0", url: "https://example.com/"), current: "1.1.0"), "links only to GitHub")
        XCTAssertNil(UpdateCheck.update(fromLatestRelease: Data("{}".utf8), current: "1.1.0"))
    }

    func testRequestSendsNoPersonalDetails() {
        let request = UpdateCheck.request
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/FNG-2002/macprompter/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "macprompter")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    @MainActor
    func testCheckerShowsDismissesAndReportsManualChecks() async {
        let checker = UpdateChecker(currentVersion: "1.1.0")
        nonisolated(unsafe) var tag = "v1.2.0"
        nonisolated(unsafe) var offline = false
        nonisolated(unsafe) var requests = 0
        checker.fetch = { request in
            requests += 1
            if offline { throw URLError(.notConnectedToInternet) }
            let data = Data(#"{"tag_name":"\#(tag)","html_url":"https://github.com/FNG-2002/macprompter/releases/tag/\#(tag)"}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await checker.check()
        XCTAssertEqual(checker.notice?.version, "1.2.0")
        checker.dismissedVersion = "1.2.0"
        XCTAssertNil(checker.notice, "closed for this version")
        tag = "v1.3.0"
        await checker.check()
        XCTAssertEqual(checker.notice?.version, "1.3.0", "a newer version shows again")
        offline = true
        await checker.check()
        XCTAssertEqual(checker.available?.version, "1.3.0", "offline keeps the last answer")
        await checker.check(manual: true)
        XCTAssertEqual(checker.message, "GitHub ist gerade nicht erreichbar. Versuche es später noch einmal.")
        offline = false; tag = "v1.1.0"
        await checker.check(manual: true)
        XCTAssertNil(checker.available)
        XCTAssertEqual(checker.message, "macprompter 1.1.0 ist aktuell.")
        XCTAssertEqual(requests, 5)
        checker.setEnabled(false)
        XCTAssertNil(checker.available)
    }

    func testUpdateCheckIsOnByDefaultAndCanBeSwitchedOff() throws {
        XCTAssertTrue(Preferences().updateCheckEnabled)
        var prefs = Preferences()
        prefs.updateCheckEnabled = false
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertFalse(decoded.updateCheckEnabled)
    }

    @MainActor
    func testTestHostNeverContactsGitHub() {
        XCTAssertTrue(AppModel.isTestHost)
        XCTAssertFalse(AppModel.shared.updates.isChecking)
        XCTAssertNil(AppModel.shared.updates.message)
    }
}
