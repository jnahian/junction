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

    func testNonMatchingURLReturnsNil() {
        let r = store.rewriter(id: "zoom")!
        XCTAssertNil(r.rewrite(URL(string: "https://zoom.us/pricing")!))
    }

    func testSlackMessageLink() {
        let r = store.rewriter(id: "slack")!
        let out = r.rewrite(URL(string: "https://myco.slack.com/archives/C024BE91L/p1234567890123456")!)
        XCTAssertEqual(out?.absoluteString, "slack://channel?id=C024BE91L&message=1234567890.123456")
    }

    func testSlackChannelLink() {
        let r = store.rewriter(id: "slack-channel")!
        let out = r.rewrite(URL(string: "https://myco.slack.com/archives/C024BE91L")!)
        XCTAssertEqual(out?.absoluteString, "slack://channel?id=C024BE91L")
    }

    func testCleanEmptyParams() {
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x=&y=1"), "a://b?y=1")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x="), "a://b")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b"), "a://b")
    }
}
