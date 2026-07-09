import XCTest
@testable import JunctionCore

final class WildcardPatternTests: XCTestCase {
    private func matches(_ pattern: String, _ url: String) -> Bool {
        guard let p = WildcardPattern(pattern) else {
            XCTFail("pattern failed to compile: \(pattern)")
            return false
        }
        guard let u = URL(string: url) else {
            XCTFail("bad url: \(url)")
            return false
        }
        return p.matches(u)
    }

    func testBareDomainMatchesDomainAndAllSubpaths() {
        XCTAssertTrue(matches("github.com", "https://github.com"))
        XCTAssertTrue(matches("github.com", "https://github.com/anthropics/claude-code"))
        XCTAssertFalse(matches("github.com", "https://gist.github.com/x"))
        XCTAssertFalse(matches("github.com", "https://github.com.evil.com/"))
    }

    func testSubdomainWildcardIncludesApex() {
        XCTAssertTrue(matches("*.github.com", "https://gist.github.com/x"))
        XCTAssertTrue(matches("*.github.com", "https://a.b.github.com/"))
        XCTAssertTrue(matches("*.github.com", "https://github.com/"))
        XCTAssertFalse(matches("*.github.com", "https://notgithub.com/"))
    }

    func testHostAndPath() {
        XCTAssertTrue(matches("app.clickup.com/*", "https://app.clickup.com/t/abc123"))
        XCTAssertTrue(matches("app.clickup.com/*", "https://app.clickup.com/"))
        XCTAssertFalse(matches("app.clickup.com/*", "https://api.clickup.com/t/abc123"))
    }

    func testAtlassianExample() {
        XCTAssertTrue(matches("*.atlassian.net/*", "https://mycorp.atlassian.net/browse/PROJ-1"))
        XCTAssertFalse(matches("*.atlassian.net/*", "https://atlassian.com/browse"))
    }

    func testSingleStarStaysWithinPathSegment() {
        XCTAssertTrue(matches("example.com/a/*/c", "https://example.com/a/b/c"))
        XCTAssertFalse(matches("example.com/a/*/c", "https://example.com/a/b/x/c"))
    }

    func testDoubleStarCrossesSegments() {
        XCTAssertTrue(matches("example.com/a/**/c", "https://example.com/a/b/x/c"))
    }

    func testTrailingStarCrossesSegments() {
        XCTAssertTrue(matches("*.zoom.us/j/*", "https://us02web.zoom.us/j/123456789"))
        XCTAssertTrue(matches("example.com/docs/*", "https://example.com/docs/a/b/c"))
    }

    func testSchemeIgnoredUnlessExplicit() {
        XCTAssertTrue(matches("example.com", "http://example.com/"))
        XCTAssertTrue(matches("https://example.com", "https://example.com/"))
        XCTAssertFalse(matches("https://example.com", "http://example.com/"))
    }

    func testHostCaseInsensitivePathCaseSensitive() {
        XCTAssertTrue(matches("Example.COM/Path", "https://example.com/Path"))
        XCTAssertFalse(matches("example.com/path", "https://example.com/PATH"))
    }

    func testQueryStringIgnored() {
        XCTAssertTrue(matches("example.com/watch", "https://example.com/watch?v=abc&t=1"))
    }

    func testLocalhostAndPorts() {
        // URL.host excludes the port, so bare "localhost" matches any port.
        XCTAssertTrue(matches("localhost", "http://localhost:3000/dashboard"))
        XCTAssertTrue(matches("localhost", "http://localhost/"))
    }

    func testInvalidPatternRejected() {
        XCTAssertNil(WildcardPattern(""))
        XCTAssertNil(WildcardPattern("   "))
        XCTAssertNil(WildcardPattern("/path/only"))
    }
}
