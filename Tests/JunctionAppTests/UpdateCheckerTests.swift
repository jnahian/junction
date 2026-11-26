#if canImport(AppKit)
import XCTest
@testable import JunctionApp

final class UpdateCheckerTests: XCTestCase {
    func testComparesComponentsAsNumbers() {
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.12.1", than: "0.12.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.12.0"))
    }

    func testSameOrOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.12.0", than: "0.12.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "0.10.0"))
    }

    func testStripsTheTagPrefix() throws {
        let json = #"{"tag_name": "v0.13.0", "html_url": "https://github.com/jnahian/junction/releases/tag/v0.13.0"}"#
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "0.13.0")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/jnahian/junction/releases/tag/v0.13.0")
    }
}
#endif
