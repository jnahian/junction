import XCTest
@testable import JunctionCore

final class TransformTests: XCTestCase {
    func testStripsKnownParams() {
        let s = TrackingParamStripper.builtin()
        let url = URL(string: "https://example.com/p?utm_source=nl&utm_medium=email&id=7&fbclid=abc")!
        XCTAssertEqual(s.strip(url).absoluteString, "https://example.com/p?id=7")
    }

    func testRemovesQueryEntirelyWhenAllParamsTracked() {
        let s = TrackingParamStripper.builtin()
        let url = URL(string: "https://example.com/p?utm_source=nl&gclid=x")!
        XCTAssertEqual(s.strip(url).absoluteString, "https://example.com/p")
    }

    func testLeavesCleanURLsUntouched() {
        let s = TrackingParamStripper.builtin()
        let url = URL(string: "https://example.com/p?a=1&b=2#frag")!
        XCTAssertEqual(s.strip(url), url)
    }

    func testNoQueryNoChange() {
        let s = TrackingParamStripper.builtin()
        let url = URL(string: "https://example.com/p")!
        XCTAssertEqual(s.strip(url), url)
    }

    func testUserExtras() {
        let s = TrackingParamStripper.builtin(extra: ["ref", "custom_*"])
        let url = URL(string: "https://example.com/?ref=hn&custom_tag=x&keep=1")!
        XCTAssertEqual(s.strip(url).absoluteString, "https://example.com/?keep=1")
    }

    func testCaseInsensitiveParamNames() {
        let s = TrackingParamStripper.builtin()
        let url = URL(string: "https://example.com/?UTM_Source=x&keep=1")!
        XCTAssertEqual(s.strip(url).absoluteString, "https://example.com/?keep=1")
    }
}

final class RewriterTests: XCTestCase {
    private let store = RewriterStore.builtin()

    func testBuiltinPackLoads() {
        XCTAssertGreaterThanOrEqual(store.rewriters.count, 9)
        XCTAssertNotNil(store.rewriter(id: "zoom"))
    }

    func testZoomWithoutPassword() {
        let r = store.rewriter(id: "zoom")!
        let out = r.rewrite(URL(string: "https://zoom.us/j/123456789")!)
        XCTAssertEqual(out?.absoluteString, "zoommtg://zoom.us/join?confno=123456789")
    }

    func testZoomWithPassword() {
        let r = store.rewriter(id: "zoom")!
        let out = r.rewrite(URL(string: "https://corp.zoom.us/j/123?pwd=abc.def")!)
        XCTAssertEqual(out?.absoluteString, "zoommtg://zoom.us/join?confno=123&pwd=abc.def")
    }

    func testFigma() {
        let r = store.rewriter(id: "figma")!
        let out = r.rewrite(URL(string: "https://www.figma.com/design/AbC123/My-File?node-id=1")!)
        XCTAssertEqual(out?.absoluteString, "figma://file/AbC123/My-File")
    }

    func testFigmaBoardAndSlides() {
        let r = store.rewriter(id: "figma")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://www.figma.com/board/AbC123/My-Board")!)?.absoluteString,
            "figma://file/AbC123/My-Board"
        )
        XCTAssertEqual(
            r.rewrite(URL(string: "https://www.figma.com/slides/AbC123/Deck")!)?.absoluteString,
            "figma://file/AbC123/Deck"
        )
    }

    func testSpotifyLocalizedLink() {
        let r = store.rewriter(id: "spotify")!
        let out = r.rewrite(URL(string: "https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC")!)
        XCTAssertEqual(out?.absoluteString, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    }

    func testNotionAppDomain() {
        let r = store.rewriter(id: "notion")!
        let out = r.rewrite(URL(string: "https://app.notion.com/Page-abc123")!)
        XCTAssertEqual(out?.absoluteString, "notion://www.notion.so/Page-abc123")
        // notion.com without the app subdomain is the marketing site, not the app.
        XCTAssertNil(r.rewrite(URL(string: "https://www.notion.com/pricing")!))
    }

    func testClickUpDoc() {
        let r = store.rewriter(id: "clickup-doc")!
        let out = r.rewrite(URL(string: "https://app.clickup.com/9018159683/v/dc/8crccj3-10918/8crccj3-6218")!)
        XCTAssertEqual(out?.absoluteString, "clickup://9018159683/v/dc/8crccj3-10918/8crccj3-6218")
    }

    func testNonMatchingURLReturnsNil() {
        let r = store.rewriter(id: "zoom")!
        XCTAssertNil(r.rewrite(URL(string: "https://zoom.us/pricing")!))
    }

    func testSlackMessageLink() {
        let r = store.rewriter(id: "slack")!
        let out = r.rewrite(
            URL(string: "https://myco.slack.com/archives/C024BE91L/p1234567890123456")!,
            lookup: ["myco": "T01ABCDEF"]
        )
        // Slack ignores the deep link without a team ID, so it must always be present.
        XCTAssertEqual(out?.absoluteString, "slack://channel?team=T01ABCDEF&id=C024BE91L&message=1234567890.123456")
    }

    func testSlackChannelLink() {
        let r = store.rewriter(id: "slack-channel")!
        let out = r.rewrite(URL(string: "https://myco.slack.com/archives/C024BE91L")!, lookup: ["myco": "T01ABCDEF"])
        XCTAssertEqual(out?.absoluteString, "slack://channel?team=T01ABCDEF&id=C024BE91L")
    }

    /// No team ID mapped → no rewrite, so the link falls back to the browser rather than
    /// opening Slack on whatever screen it happened to be showing.
    func testSlackWithoutMappedTeamDoesNotRewrite() {
        let r = store.rewriter(id: "slack")!
        XCTAssertNil(r.rewrite(URL(string: "https://myco.slack.com/archives/C024BE91L/p1234567890123456")!))
        XCTAssertNil(r.rewrite(
            URL(string: "https://myco.slack.com/archives/C024BE91L/p1234567890123456")!,
            lookup: ["other": "T01ABCDEF"]
        ))
    }

    func testClickUpTask() {
        let r = store.rewriter(id: "clickup")!
        let out = r.rewrite(URL(string: "https://app.clickup.com/t/86cxk2m1q")!)
        XCTAssertEqual(out?.absoluteString, "clickup://t/86cxk2m1q")
    }

    func testGitHubDesktopRepoRootOnly() {
        let r = store.rewriter(id: "github-desktop")!
        let out = r.rewrite(URL(string: "https://github.com/jnahian/junction")!)
        XCTAssertEqual(out?.absoluteString, "x-github-client://openRepo/https://github.com/jnahian/junction")
        // Sub-pages (issues, PRs, files) must NOT be hijacked into the desktop app.
        XCTAssertNil(r.rewrite(URL(string: "https://github.com/jnahian/junction/pull/42")!))
        XCTAssertNil(r.rewrite(URL(string: "https://github.com/jnahian/junction/issues")!))
    }

    func testTelegram() {
        let r = store.rewriter(id: "telegram")!
        let out = r.rewrite(URL(string: "https://t.me/durov")!)
        XCTAssertEqual(out?.absoluteString, "tg://resolve?domain=durov")
        // Invite links (t.me/+hash) use a different scheme path — leave them alone.
        XCTAssertNil(r.rewrite(URL(string: "https://t.me/+AbCdEf123")!))
    }

    func testAppleMusic() {
        let r = store.rewriter(id: "apple-music")!
        let out = r.rewrite(URL(string: "https://music.apple.com/us/album/blue/1440835967")!)
        XCTAssertEqual(out?.absoluteString, "music://music.apple.com/us/album/blue/1440835967")
    }

    func testCleanEmptyParams() {
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x=&y=1"), "a://b?y=1")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x="), "a://b")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b"), "a://b")
    }
}
