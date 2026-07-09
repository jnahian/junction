import XCTest
@testable import JunctionCore

final class RoutingEngineTests: XCTestCase {
    private func makeConfig() -> Config {
        Config(
            fallback: Fallback(app: "com.apple.Safari"),
            stripTrackingParams: true,
            rules: [
                Rule(
                    name: "Work → Chrome work profile",
                    match: Match(patterns: ["*.atlassian.net/*", "app.clickup.com/*"]),
                    action: .open(app: "com.google.Chrome", profile: "Profile 1")
                ),
                Rule(
                    name: "Zoom → native",
                    match: Match(patterns: ["*.zoom.us/j/*", "*.zoom.us/w/*"]),
                    action: .deepLink("zoom")
                ),
                Rule(
                    name: "Terminal → Chrome",
                    match: Match(sourceApps: ["com.apple.Terminal", "com.googlecode.iterm2"]),
                    action: .open(app: "com.google.Chrome", profile: nil)
                ),
                Rule(
                    name: "Meet from Calendar → picker",
                    match: Match(patterns: ["meet.google.com/*"], sourceApps: ["com.apple.iCal"]),
                    action: .prompt
                ),
            ]
        )
    }

    private func engine(_ config: Config? = nil, schemeHandled: @escaping @Sendable (String) -> Bool = { _ in true }) -> RoutingEngine {
        RoutingEngine(config: config ?? makeConfig(), rewriters: .builtin(), isSchemeHandled: schemeHandled)
    }

    private func event(_ url: String, source: String? = nil, forcePicker: Bool = false) -> LinkEvent {
        LinkEvent(url: URL(string: url)!, sourceApp: source, forcePicker: forcePicker)
    }

    func testFirstMatchWins() {
        let d = engine().route(event("https://mycorp.atlassian.net/browse/X-1", source: "com.apple.Terminal"))
        // Rule 1 (patterns) fires before rule 3 (Terminal source).
        guard case .open(let app, let profile, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(app, "com.google.Chrome")
        XCTAssertEqual(profile, "Profile 1")
    }

    func testSourceAppOnlyRuleMatchesAnyURL() {
        let d = engine().route(event("https://example.org/x", source: "com.googlecode.iterm2"))
        guard case .open(let app, let profile, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(app, "com.google.Chrome")
        XCTAssertNil(profile)
    }

    func testPatternAndSourceAreANDed() {
        // meet.google.com from a non-calendar app: rule 4 must NOT fire → fallback.
        let d = engine().route(event("https://meet.google.com/abc-defg-hij", source: "com.tinyspeck.slackmacgap"))
        guard case .fallback(let app, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(app, "com.apple.Safari")

        let d2 = engine().route(event("https://meet.google.com/abc-defg-hij", source: "com.apple.iCal"))
        guard case .prompt = d2 else { return XCTFail("\(d2)") }
    }

    func testNoMatchFallsBack() {
        let d = engine().route(event("https://unmatched.example/x"))
        guard case .fallback(let app, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(app, "com.apple.Safari")
    }

    func testDeepLinkAction() {
        let d = engine().route(event("https://us02web.zoom.us/j/9876543210?pwd=s3cret"))
        guard case .deepLink(let url, let id, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(id, "zoom")
        XCTAssertEqual(url.scheme, "zoommtg")
        XCTAssertTrue(url.absoluteString.contains("confno=9876543210"))
        XCTAssertTrue(url.absoluteString.contains("pwd=s3cret"))
    }

    func testDeepLinkFallsBackWhenAppMissing() {
        let d = engine(schemeHandled: { _ in false })
            .route(event("https://us02web.zoom.us/j/9876543210"))
        guard case .fallback = d else { return XCTFail("\(d)") }
    }

    func testTrackingParamsStrippedBeforeRouting() {
        let d = engine().route(event("https://unmatched.example/a?utm_source=x&keep=1&fbclid=zzz"))
        XCTAssertEqual(d.url.absoluteString, "https://unmatched.example/a?keep=1")
    }

    func testStripDisabled() {
        var config = makeConfig()
        config.stripTrackingParams = false
        let d = engine(config).route(event("https://unmatched.example/a?utm_source=x"))
        XCTAssertEqual(d.url.absoluteString, "https://unmatched.example/a?utm_source=x")
    }

    func testForcePickerBeatsRules() {
        let d = engine().route(event("https://mycorp.atlassian.net/browse/X-1", forcePicker: true))
        guard case .prompt = d else { return XCTFail("\(d)") }
    }

    func testDisabledRuleSkipped() {
        var config = makeConfig()
        config.rules[0].enabled = false
        let d = engine(config).route(event("https://mycorp.atlassian.net/browse/X-1"))
        guard case .fallback = d else { return XCTFail("\(d)") }
    }

    func testBuiltinRewriterFiresWhenNoRuleMatches() {
        // Spotify has no user rule, but the built-in rewriter is enabled by default.
        let d = engine().route(event("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
        guard case .deepLink(let url, let id, _) = d else { return XCTFail("\(d)") }
        XCTAssertEqual(id, "spotify")
        XCTAssertEqual(url.absoluteString, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    }

    func testDisabledRewriterSkipped() {
        var config = makeConfig()
        config.disabledRewriters = ["spotify"]
        let d = engine(config).route(event("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
        guard case .fallback = d else { return XCTFail("\(d)") }
    }

    func testPerRuleRewrite() {
        var config = makeConfig()
        config.rules.append(Rule(
            name: "Old wiki → new wiki",
            match: Match(patterns: ["wiki.old.example/*"]),
            action: .open(app: "com.apple.Safari", profile: nil),
            rewrite: RegexRewrite(find: "//wiki\\.old\\.example/", replace: "//wiki.new.example/")
        ))
        let d = engine(config).route(event("https://wiki.old.example/page"))
        XCTAssertEqual(d.url.absoluteString, "https://wiki.new.example/page")
    }

    func testTraceReportsMatchedRule() {
        let t = engine().trace(event("https://app.clickup.com/t/1?utm_medium=email"))
        XCTAssertEqual(t.matchedRule, "Work → Chrome work profile")
        XCTAssertEqual(t.matchedRuleIndex, 0)
        XCTAssertEqual(t.transformedURL.absoluteString, "https://app.clickup.com/t/1")
    }

    func testRegexMatcher() {
        let config = Config(rules: [
            Rule(
                name: "PR links",
                match: Match(regex: "github\\.com/.+/pull/\\d+"),
                action: .clipboard
            ),
        ])
        let d = engine(config).route(event("https://github.com/o/r/pull/42"))
        guard case .clipboard = d else { return XCTFail("\(d)") }
    }
}
