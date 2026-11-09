import XCTest
@testable import MacPrompter

/// Release metadata the About panel, the release workflow and license compliance rely on.
final class AppBundleTests: XCTestCase {
    func testVersionIsSemanticAndBuildNumberIsNumeric() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        XCTAssertNotNil(version.wholeMatch(of: /\d+\.\d+\.\d+/), version)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertNotNil(Int(build), build)
        XCTAssertNotNil(info["NSHumanReadableCopyright"] as? String)
    }

    func testThirdPartyLicensesShipWithTheApp() throws {
        let credits = try String(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "Credits", withExtension: "html")), encoding: .utf8)
        for required in ["MIT License (macprompter)", "Fayaz Ahmed", "OpenDyslexic", "Permission is hereby granted"] {
            XCTAssertTrue(credits.contains(required), required)
        }
        let ofl = try String(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "OFL", withExtension: "txt")), encoding: .utf8)
        XCTAssertTrue(ofl.contains("SIL OPEN FONT LICENSE Version 1.1"))
    }

    func testVersionLabelComesFromTheBundle() {
        XCTAssertEqual(AppInfo.versionLabel(["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "7"]), "Version 1.2.3 (7)")
        XCTAssertTrue(AppInfo.versionLabel().hasPrefix("Version \(Bundle.main.infoDictionary!["CFBundleShortVersionString"]!)"))
    }

    func testProjectLinksPointToTheRepository() {
        for url in [AppInfo.repository, AppInfo.releases, AppInfo.newIssue] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host(), "github.com")
            XCTAssertTrue(url.path().hasPrefix("/FNG-2002/macprompter"), url.absoluteString)
        }
    }
}
