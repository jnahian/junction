import XCTest
@testable import JunctionCore

final class JSONCTests: XCTestCase {
    func testStripsLineComments() {
        let input = "{\n  // hello\n  \"a\": 1\n}"
        let data = JSONC.data(from: Data(input.utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testStripsBlockComments() {
        let input = "{ /* multi\nline */ \"a\": 1 }"
        let data = JSONC.data(from: Data(input.utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testRemovesTrailingCommas() {
        let input = "{ \"a\": [1, 2, 3,], \"b\": { \"c\": 1, }, }"
        let data = JSONC.data(from: Data(input.utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testPreservesSlashesAndCommentsInsideStrings() {
        let input = "{ \"url\": \"https://x.example/a,b\", \"note\": \"not // a comment, nor /* this */\" }"
        let out = JSONC.toStrictJSON(input)
        XCTAssertTrue(out.contains("https://x.example/a,b"))
        XCTAssertTrue(out.contains("not // a comment, nor /* this */"))
    }

    func testPreservesEscapedQuotes() {
        let input = "{ \"a\": \"say \\\"hi\\\" // ok\" }"
        let out = JSONC.toStrictJSON(input)
        XCTAssertTrue(out.contains("say \\\"hi\\\" // ok"))
    }
}

final class ConfigStoreTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("junction-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private var configURL: URL { tmpDir.appendingPathComponent("config.json") }

    func testPRDExampleConfigParses() throws {
        let json = """
        {
          "version": 1,
          "fallback": { "app": "com.apple.Safari" },
          "stripTrackingParams": true,
          "rules": [
            {
              "name": "Work links → Chrome work profile",
              "match": {
                "patterns": ["*.atlassian.net/*", "app.clickup.com/*", "*.slack.com/*"],
                "sourceApps": []
              },
              "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
            },
            {
              "name": "Zoom → native app",
              "match": { "patterns": ["*.zoom.us/j/*", "*.zoom.us/w/*"] },
              "action": { "deepLink": "zoom" }
            },
            {
              "name": "Links from Terminal → Chrome",
              "match": { "sourceApps": ["com.googlecode.iterm2", "com.apple.Terminal"] },
              "action": { "app": "com.google.Chrome" }
            },
            {
              "name": "Meeting links from calendar → picker",
              "match": { "patterns": ["meet.google.com/*"], "sourceApps": ["com.apple.iCal"] },
              "action": { "prompt": true }
            }
          ]
        }
        """
        try Data(json.utf8).write(to: configURL)
        let config = try ConfigStore.load(from: configURL)
        XCTAssertEqual(config.rules.count, 4)
        XCTAssertEqual(config.rules[0].action, .open(app: "com.google.Chrome", profile: "Profile 1"))
        XCTAssertEqual(config.rules[1].action, .deepLink("zoom"))
        XCTAssertEqual(config.rules[3].action, .prompt)
    }

    func testJSONCConfigParses() throws {
        let json = """
        {
          // my dotfiles config
          "fallback": { "app": "com.apple.Safari" },
          "rules": [
            {
              "name": "GitHub",
              "match": { "patterns": ["github.com"] },
              "action": { "app": "org.mozilla.firefox" },
            },
          ],
        }
        """
        try Data(json.utf8).write(to: configURL)
        let config = try ConfigStore.load(from: configURL)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertTrue(config.stripTrackingParams, "defaults apply for omitted keys")
    }

    func testSaveWritesStrictSortedJSONAndRoundTrips() throws {
        let store = ConfigStore(fileURL: configURL)
        var config = Config()
        config.rules = [
            Rule(name: "Test", match: Match(patterns: ["example.com"]), action: .clipboard)
        ]
        try store.save(config)

        let onDisk = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(onDisk.contains("//"), "no comments in written output apart from URLs")
        let reloaded = try ConfigStore.load(from: configURL)
        XCTAssertEqual(reloaded, config)

        // Stable output: saving the same config twice produces identical bytes (clean git diffs).
        let first = try Data(contentsOf: configURL)
        try store.save(config)
        XCTAssertEqual(first, try Data(contentsOf: configURL))
    }

    func testLoopGuardRejectsJunctionAsTarget() {
        let config = Config(rules: [
            Rule(
                name: "Loop",
                match: Match(patterns: ["example.com"]),
                action: .open(app: ConfigStore.junctionBundleID, profile: nil)
            ),
        ])
        XCTAssertFalse(ConfigStore.validate(config).isEmpty)
    }

    func testInvalidRegexReported() {
        let config = Config(rules: [
            Rule(name: "Bad", match: Match(regex: "("), action: .clipboard),
        ])
        XCTAssertFalse(ConfigStore.validate(config).isEmpty)
    }

    func testRuleWithoutMatchersReported() {
        let config = Config(rules: [
            Rule(name: "Empty", match: Match(), action: .clipboard),
        ])
        XCTAssertFalse(ConfigStore.validate(config).isEmpty)
    }

    func testInvalidFileKeepsLastGood() throws {
        let store = ConfigStore(fileURL: configURL)
        var config = Config()
        config.rules = [Rule(name: "Keep me", match: Match(patterns: ["example.com"]), action: .clipboard)]
        try store.save(config)

        try Data("{ not json".utf8).write(to: configURL)
        store.reload()
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.config.rules.first?.name, "Keep me", "last-good config retained")
    }

    func testMissingActionFailsParse() throws {
        let json = """
        { "rules": [ { "name": "x", "match": { "patterns": ["a.com"] }, "action": {} } ] }
        """
        try Data(json.utf8).write(to: configURL)
        XCTAssertThrowsError(try ConfigStore.load(from: configURL))
    }
}
