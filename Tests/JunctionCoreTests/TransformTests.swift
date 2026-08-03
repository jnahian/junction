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

    func testFigmaPreservesNodeID() {
        let r = store.rewriter(id: "figma")!
        // node-id is what points the desktop app at the linked frame. Dropping it opened
        // the file but left the app unable to navigate to the node (the reported bug).
        XCTAssertEqual(
            r.rewrite(URL(string: "https://www.figma.com/design/AbC123/My-File?node-id=15698-98442")!)?.absoluteString,
            "figma://file/AbC123/My-File?node-id=15698-98442"
        )
        // Share links carry a `t=` token alongside node-id — keep the whole query.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://www.figma.com/design/daCjzGc1Lz6FdNMuEoZkH7/StoreSEO-Deliverable?node-id=15698-98442&t=lREo598oCMUAQutK-1")!)?.absoluteString,
            "figma://file/daCjzGc1Lz6FdNMuEoZkH7/StoreSEO-Deliverable?node-id=15698-98442&t=lREo598oCMUAQutK-1"
        )
        // No query → unchanged path, and no dangling `?`.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://www.figma.com/design/AbC123/My-File")!)?.absoluteString,
            "figma://file/AbC123/My-File"
        )
    }

    func testFigmaNonDesignFileTypes() {
        let r = store.rewriter(id: "figma")!
        // Every file type normalizes to figma://file/<key>, as design links already did.
        for (path, expected) in [
            ("board/AbC123/My-Board", "figma://file/AbC123/My-Board"),
            ("slides/AbC123/Deck", "figma://file/AbC123/Deck"),
            ("deck/AbC123/Deck", "figma://file/AbC123/Deck"),
            ("proto/AbC123/Flow", "figma://file/AbC123/Flow"),
        ] {
            let out = r.rewrite(URL(string: "https://www.figma.com/\(path)")!)
            XCTAssertEqual(out?.absoluteString, expected, path)
        }
    }

    func testSpotifyLocalizedLink() {
        let r = store.rewriter(id: "spotify")!
        for locale in ["intl-de", "intl-pt-br"] {
            let out = r.rewrite(URL(string: "https://open.spotify.com/\(locale)/track/4uLU6hMCjMI75M1A2tKUQC")!)
            XCTAssertEqual(out?.absoluteString, "spotify:track:4uLU6hMCjMI75M1A2tKUQC", locale)
        }
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
        // A doc's own page, and a page inside it.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/9018159683/v/dc/8crccj3-10918")!)?.absoluteString,
            "clickup://9018159683/v/dc/8crccj3-10918"
        )
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/9018159683/v/dc/8crccj3-10918/8crccj3-6218")!)?.absoluteString,
            "clickup://9018159683/v/dc/8crccj3-10918/8crccj3-6218"
        )
        // A trailing slash is not part of the doc's address.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/9018159683/v/dc/8crccj3-10918/?block=x")!)?.absoluteString,
            "clickup://9018159683/v/dc/8crccj3-10918"
        )
        // Task links belong to the `clickup` rewriter, not this one.
        XCTAssertNil(r.rewrite(URL(string: "https://app.clickup.com/t/86ey9pu32")!))
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

    /// The address bar (and "Copy link" with custom task IDs on) scopes a task to its
    /// workspace. Capturing only the first segment would deep-link to the workspace ID —
    /// a valid-looking URL that opens ClickUp on the wrong screen.
    func testClickUpWorkspaceScopedTask() {
        let r = store.rewriter(id: "clickup")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/t/9018159683/DEV-1234")!)?.absoluteString,
            "clickup://t/9018159683/DEV-1234"
        )
        // Sub-paths of a task ride along too.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/t/86cxk2m1q/comment/123")!)?.absoluteString,
            "clickup://t/86cxk2m1q/comment/123"
        )
        // Query, fragment and a trailing slash are still dropped.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://app.clickup.com/t/86cxk2m1q/?block=abc")!)?.absoluteString,
            "clickup://t/86cxk2m1q"
        )
        // No task at all → no rewrite, so the link falls back to the browser.
        XCTAssertNil(r.rewrite(URL(string: "https://app.clickup.com/t/")!))
        // Doc links belong to the `clickup-doc` rewriter, not this one.
        XCTAssertNil(r.rewrite(URL(string: "https://app.clickup.com/9018159683/v/dc/8crccj3-10918")!))
    }

    func testGitHubDesktopRepoRootOnly() {
        let r = store.rewriter(id: "github-desktop")!
        let out = r.rewrite(URL(string: "https://github.com/jnahian/junction")!)
        XCTAssertEqual(out?.absoluteString, "x-github-client://openRepo/https://github.com/jnahian/junction")
        // Sub-pages (issues, PRs, files) must NOT be hijacked into the desktop app.
        XCTAssertNil(r.rewrite(URL(string: "https://github.com/jnahian/junction/pull/42")!))
        XCTAssertNil(r.rewrite(URL(string: "https://github.com/jnahian/junction/issues")!))
    }

    /// GitHub's own two-segment pages look exactly like `owner/repo`. Sending them to the
    /// desktop app asks it to clone a repository that doesn't exist.
    func testGitHubDesktopIgnoresReservedPaths() {
        let r = store.rewriter(id: "github-desktop")!
        for path in ["settings/profile", "features/actions", "orgs/anthropics",
                     "sponsors/someone", "topics/swift", "users/jnahian"] {
            XCTAssertNil(r.rewrite(URL(string: "https://github.com/\(path)")!), path)
        }
        // The reserved list matches whole segments only — an owner may start with one.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://github.com/newrelic/newrelic-ruby-agent")!)?.absoluteString,
            "x-github-client://openRepo/https://github.com/newrelic/newrelic-ruby-agent"
        )
    }

    func testLinear() {
        let r = store.rewriter(id: "linear")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://linear.app/acme/issue/ENG-123/fix-the-thing")!)?.absoluteString,
            "linear://linear.app/acme/issue/ENG-123/fix-the-thing"
        )
        XCTAssertEqual(
            r.rewrite(URL(string: "https://linear.app/acme/my-issues")!)?.absoluteString,
            "linear://linear.app/acme/my-issues"
        )
        // linear.app is also Linear's marketing and docs site — those pages are for a
        // browser, and the app has nothing to show for them.
        XCTAssertNil(r.rewrite(URL(string: "https://linear.app/pricing")!))
        XCTAssertNil(r.rewrite(URL(string: "https://linear.app/docs/api-reference")!))
        XCTAssertNil(r.rewrite(URL(string: "https://linear.app/blog/issue-tracking-for-teams")!))
    }

    func testTeamsNewDomains() {
        let r = store.rewriter(id: "teams")!
        for host in ["teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com"] {
            XCTAssertEqual(
                r.rewrite(URL(string: "https://\(host)/l/meetup-join/19%3ameeting_abc/0")!)?.absoluteString,
                "msteams:/l/meetup-join/19%3ameeting_abc/0",
                host
            )
        }
    }

    func testDiscordLegacyDomain() {
        let r = store.rewriter(id: "discord")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://discordapp.com/channels/123/456")!)?.absoluteString,
            "discord://-/channels/123/456"
        )
    }

    func testTodoistWithoutAppSubdomain() {
        let r = store.rewriter(id: "todoist")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://todoist.com/app/task/buy-milk-6X4rfFVPjhLQ")!)?.absoluteString,
            "todoist://task?id=6X4rfFVPjhLQ"
        )
    }

    func testTelegram() {
        let r = store.rewriter(id: "telegram")!
        let out = r.rewrite(URL(string: "https://t.me/durov")!)
        XCTAssertEqual(out?.absoluteString, "tg://resolve?domain=durov")
        // Invite links (t.me/+hash) use a different scheme path — leave them alone.
        XCTAssertNil(r.rewrite(URL(string: "https://t.me/+AbCdEf123")!))
    }

    /// A link to a single post carries the message number; without it Telegram opens the
    /// channel at the bottom instead of the message someone sent you.
    func testTelegramPost() {
        let r = store.rewriter(id: "telegram")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://t.me/durov/123")!)?.absoluteString,
            "tg://resolve?domain=durov&post=123"
        )
        XCTAssertEqual(
            r.rewrite(URL(string: "https://t.me/durov/123?single")!)?.absoluteString,
            "tg://resolve?domain=durov&post=123"
        )
        // Non-numeric second segments aren't posts (t.me/s/name is a web preview).
        XCTAssertNil(r.rewrite(URL(string: "https://t.me/s/durov")!))
    }

    func testAppleMusic() {
        let r = store.rewriter(id: "apple-music")!
        let out = r.rewrite(URL(string: "https://music.apple.com/us/album/blue/1440835967")!)
        XCTAssertEqual(out?.absoluteString, "music://music.apple.com/us/album/blue/1440835967")
    }

    /// A song lives at its album's address with `?i=<trackID>`. Dropping the query opens
    /// the album at track 1 — the right record, the wrong song.
    func testAppleMusicSongKeepsTrackID() {
        let r = store.rewriter(id: "apple-music")!
        XCTAssertEqual(
            r.rewrite(URL(string: "https://music.apple.com/us/album/blue/1440835967?i=1440836193")!)?.absoluteString,
            "music://music.apple.com/us/album/blue/1440835967?i=1440836193"
        )
        // `i` doesn't have to come first, and everything else in the query still goes.
        XCTAssertEqual(
            r.rewrite(URL(string: "https://music.apple.com/us/album/blue/1440835967?l=en&i=1440836193")!)?.absoluteString,
            "music://music.apple.com/us/album/blue/1440835967?i=1440836193"
        )
    }

    func testAppStore() {
        let r = store.rewriter(id: "app-store")!
        let out = r.rewrite(URL(string: "https://apps.apple.com/us/app/things-3/id904237743")!)
        XCTAssertEqual(out?.absoluteString, "macappstore://apps.apple.com/us/app/things-3/id904237743")
    }

    func testCleanEmptyParams() {
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x=&y=1"), "a://b?y=1")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b?x="), "a://b")
        XCTAssertEqual(Rewriter.cleanEmptyParams("a://b"), "a://b")
    }
}
