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
        config.fallback = Fallback(app: Fallback.picker)
        config.pickerHidden = ["org.mozilla.firefox", "com.google.Chrome/Profile 2"]
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

    func testSaveWritesThroughSymlink() throws {
        let dotfile = tmpDir.appendingPathComponent("dotfiles/config.json")
        try FileManager.default.createDirectory(at: dotfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dotfile)
        try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: dotfile)

        var config = Config()
        config.fallback = Fallback(app: "com.google.Chrome")
        try ConfigStore(fileURL: configURL).save(config)

        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: configURL.path), "link survives")
        XCTAssertEqual(try ConfigStore.load(from: dotfile), config, "the linked file gets the change")
    }

    /// GNU Stow writes relative links.
    func testSaveWritesThroughRelativeSymlink() throws {
        let dotfile = tmpDir.appendingPathComponent("dotfiles/config.json")
        try FileManager.default.createDirectory(at: dotfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dotfile)
        try FileManager.default.createSymbolicLink(atPath: configURL.path, withDestinationPath: "dotfiles/config.json")

        var config = Config()
        config.fallback = Fallback(app: "com.google.Chrome")
        try ConfigStore(fileURL: configURL).save(config)

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: configURL.path),
            "dotfiles/config.json"
        )
        XCTAssertEqual(try ConfigStore.load(from: dotfile), config)
    }

    func testDanglingSymlinkIsReportedAndLeftAlone() throws {
        let target = tmpDir.appendingPathComponent("elsewhere/config.json")
        try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: target)

        let store = ConfigStore(fileURL: configURL)
        XCTAssertNotNil(store.lastError, "a link to nowhere must not look like a first launch")

        store.bootstrapIfMissing()
        XCTAssertThrowsError(try store.save(Config()))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: configURL.path), "link survives")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "defaults aren't written over rules that may be on their way")
    }

    #if canImport(Darwin)
    func testWatcherReloadsWhenADanglingLinkRecovers() throws {
        let target = tmpDir.appendingPathComponent("elsewhere/config.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: target)

        let store = ConfigStore(fileURL: configURL)
        let reloaded = expectation(description: "config reloaded")
        store.onChange = { _ in reloaded.fulfill() }
        store.startWatching()
        defer { store.stopWatching() }

        try Data(#"{"fallback": {"app": "com.google.Chrome"}}"#.utf8).write(to: target)
        wait(for: [reloaded], timeout: 5)
        XCTAssertEqual(store.config.fallback.app, "com.google.Chrome")
        XCTAssertNil(store.lastError)
    }

    /// The app loads the config at launch but starts watching later. A link that recovers in
    /// between must not leave the warning and the default rules up until the next edit.
    func testWatcherCatchesUpOnALinkThatRecoveredBeforeWatching() throws {
        let target = tmpDir.appendingPathComponent("elsewhere/config.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: target)

        let store = ConfigStore(fileURL: configURL)
        XCTAssertNotNil(store.lastError)
        try Data(#"{"fallback": {"app": "com.google.Chrome"}}"#.utf8).write(to: target)

        let reloaded = expectation(description: "config reloaded")
        store.onChange = { _ in reloaded.fulfill() }
        store.startWatching()
        defer { store.stopWatching() }

        wait(for: [reloaded], timeout: 5)
        XCTAssertEqual(store.config.fallback.app, "com.google.Chrome")
        XCTAssertNil(store.lastError)
    }
    #endif

    /// The GUI's "Add App…" writes custom rewriters; the CLI and the engine read them back.
    func testCustomRewriterSurvivesSaveAndLoad() throws {
        let store = ConfigStore(fileURL: configURL)
        var config = Config()
        config.customRewriters = [
            Rewriter(id: "linear", name: "Linear", patterns: ["^https?://linear\\.app/(.*)$"],
                     template: "linear://$1", scheme: "linear"),
        ]
        config.enabledRewriters = ["linear"]
        try store.save(config)

        let reloaded = try ConfigStore.load(from: configURL)
        XCTAssertEqual(reloaded, config)
        XCTAssertEqual(reloaded.customRewriters.first?.template, "linear://$1")
    }

    func testInvalidCustomRewriterReported() {
        var config = Config()
        config.customRewriters = [
            Rewriter(id: "bad", name: "Bad", patterns: ["("], template: "x://$1", scheme: "x"),
            Rewriter(id: "bad", name: "Dupe", patterns: ["^https://x"], template: "x://", scheme: ""),
        ]
        let problems = ConfigStore.validate(config)
        XCTAssertTrue(problems.contains { $0.contains("invalid pattern") })
        XCTAssertTrue(problems.contains { $0.contains("duplicate id") })
        XCTAssertTrue(problems.contains { $0.contains("URL scheme") })
    }

    /// A rule deep-linking to an app that doesn't exist can never fire — say so, don't route it silently.
    func testUnknownDeepLinkTargetReported() {
        var config = Config(rules: [
            Rule(name: "Gone", match: Match(patterns: ["gone.example/*"]), action: .deepLink("gone")),
        ])
        XCTAssertTrue(ConfigStore.validate(config).contains { $0.contains("unknown deep-link app") })

        config.customRewriters = [
            Rewriter(id: "gone", name: "Gone", patterns: ["^https://gone"], template: "gone://", scheme: "gone"),
        ]
        XCTAssertTrue(ConfigStore.validate(config).isEmpty)
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

    func testPickerAppearanceAbsentStaysAbsentOnSave() throws {
        try Data(#"{ "fallback": { "app": "com.apple.Safari" } }"#.utf8).write(to: configURL)
        let config = try ConfigStore.load(from: configURL)
        XCTAssertNil(config.picker, "no block means the original vertical list with names")
        try ConfigStore(fileURL: configURL).save(config)
        let onDisk = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(onDisk.contains("\"picker\""), "an untouched config must not grow a picker block")
    }

    func testPickerAppearanceRoundTripsAndClampsIconSize() throws {
        let json = #"{ "picker": { "layout": "horizontal", "labels": "none", "iconSize": 400 } }"#
        try Data(json.utf8).write(to: configURL)
        let config = try ConfigStore.load(from: configURL)
        XCTAssertEqual(config.picker, PickerAppearance(layout: .horizontal, labels: .iconOnly, iconSize: 64))
        XCTAssertEqual(PickerAppearance(iconSize: 1).iconSize, 16)

        try ConfigStore(fileURL: configURL).save(config)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        let picker = saved?["picker"] as? [String: Any]
        XCTAssertEqual(picker?["labels"] as? String, "none", "the file keeps the documented value")
        XCTAssertEqual(try ConfigStore.load(from: configURL), config)
    }

    func testUnknownPickerLayoutNamesItsLocation() throws {
        try Data(#"{ "picker": { "layout": "sideways" } }"#.utf8).write(to: configURL)
        XCTAssertThrowsError(try ConfigStore.load(from: configURL)) { error in
            XCTAssertTrue("\(error)".contains("picker.layout"), "got: \(error)")
        }
    }
}
