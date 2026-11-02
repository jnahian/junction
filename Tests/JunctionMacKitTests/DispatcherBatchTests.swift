#if canImport(AppKit)
import AppKit
import JunctionCore
import XCTest
@testable import JunctionMacKit

final class DispatcherBatchTests: XCTestCase {
    private let urls = [
        URL(string: "https://example.com/first")!,
        URL(string: "https://example.com/second")!,
        URL(string: "https://example.com/first")!
    ]
    private let appURL = URL(fileURLWithPath: "/Applications/Test Browser.app")

    private func environment() -> Dispatcher.Environment {
        Dispatcher.Environment(
            applicationURL: { _ in self.appURL },
            family: { _ in .other },
            firefoxProfileExists: { _, _ in true },
            chromiumProfiles: { _ in [BrowserProfile(directory: "Work", displayName: "Work")] },
            webApp: { _ in nil },
            webAppProfile: { _ in nil },
            openURLs: { _, _, _, _ in XCTFail("Unexpected native URL request") },
            openApplication: { _, _, _ in XCTFail("Unexpected process launch") },
            openDefault: { _ in XCTFail("Unexpected default-browser fallback") }
        )
    }

    func testNormalBrowserReceivesOneOrderedBatch() {
        var environment = environment()
        var resolutions: [String] = []
        var requests: [[URL]] = []
        environment.applicationURL = { id in resolutions.append(id); return self.appURL }
        environment.openURLs = { urls, appURL, configuration, _ in
            requests.append(urls)
            XCTAssertEqual(appURL, self.appURL)
            XCTAssertTrue(configuration.activates)
            XCTAssertFalse(configuration.createsNewApplicationInstance)
        }
        Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "test.browser", profile: nil, urls: urls)
        XCTAssertEqual(resolutions, ["test.browser"])
        XCTAssertEqual(requests, [urls])
    }

    func testProfilesLaunchOneProcessWithEveryURL() {
        for (family, flags) in [(BrowserFamily.chromium, ["--profile-directory=Work"]), (.firefox, ["-P", "Work"])] {
            var environment = environment()
            var launches: [[String]] = []
            environment.family = { _ in family }
            environment.openApplication = { _, configuration, _ in
                launches.append(configuration.arguments)
                XCTAssertTrue(configuration.createsNewApplicationInstance)
            }
            Dispatcher(fallbackApp: "picker", environment: environment)
                .openInBrowser(bundleID: "test.browser", profile: "Work", urls: urls)
            XCTAssertEqual(launches, [flags + urls.map(\.absoluteString)])
        }
    }

    func testMissingBrowserReturnsOneRetryWithoutLaunching() {
        var environment = environment()
        environment.applicationURL = { _ in nil }
        let completed = expectation(description: "one retry completion")
        completed.assertForOverFulfill = true
        let outcome = Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "missing", profile: nil, urls: urls) { outcome in
                if case .needsPicker = outcome {} else { XCTFail("Expected retry") }
                completed.fulfill()
            }
        if case .needsPicker = outcome {} else { XCTFail("Expected immediate retry") }
        wait(for: [completed], timeout: 1)
    }

    func testDeletedFirefoxProfileFallsBackOnceForEntireBatch() {
        var environment = environment()
        let fallbackURL = URL(fileURLWithPath: "/Applications/Fallback.app")
        environment.applicationURL = { $0 == "fallback" ? fallbackURL : self.appURL }
        environment.family = { _ in .firefox }
        environment.firefoxProfileExists = { _, _ in false }
        var requests: [[URL]] = []
        environment.openURLs = { urls, target, configuration, _ in
            requests.append(urls)
            XCTAssertEqual(target, fallbackURL)
            XCTAssertTrue(configuration.arguments.isEmpty)
        }
        let outcome = Dispatcher(fallbackApp: "fallback", environment: environment)
            .openInBrowser(bundleID: "firefox", profile: "deleted", urls: urls)
        XCTAssertEqual(requests, [urls])
        if case .degradedToFallback = outcome {} else { XCTFail("Expected degraded result") }
    }

    /// `Profile 2` is Work on the Mac that wrote the rule; here Work is `Profile 5`, and
    /// `Profile 2` is someone else.
    func testChromiumProfileResolvesByNameAcrossMacs() {
        var environment = environment()
        environment.family = { _ in .chromium }
        environment.chromiumProfiles = { _ in [
            BrowserProfile(directory: "Profile 2", displayName: "Personal"),
            BrowserProfile(directory: "Profile 5", displayName: "Work"),
        ] }
        var launches: [[String]] = []
        environment.openApplication = { _, configuration, _ in launches.append(configuration.arguments) }
        Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "test.browser", profile: "Work", urls: urls)
        XCTAssertEqual(launches, [["--profile-directory=Profile 5"] + urls.map(\.absoluteString)])
    }

    func testChromiumDirectoryValueStillWorks() {
        var environment = environment()
        environment.family = { _ in .chromium }
        environment.chromiumProfiles = { _ in [BrowserProfile(directory: "Profile 2", displayName: "Personal")] }
        var launches: [[String]] = []
        environment.openApplication = { _, configuration, _ in launches.append(configuration.arguments) }
        Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "test.browser", profile: "Profile 2", urls: urls)
        XCTAssertEqual(launches, [["--profile-directory=Profile 2"] + urls.map(\.absoluteString)])
    }

    func testMissingChromiumProfileFallsBackOnceForEntireBatch() {
        var environment = environment()
        let fallbackURL = URL(fileURLWithPath: "/Applications/Fallback.app")
        environment.applicationURL = { $0 == "fallback" ? fallbackURL : self.appURL }
        environment.family = { $0 == "fallback" ? .other : .chromium }
        environment.chromiumProfiles = { _ in [BrowserProfile(directory: "Default", displayName: "Personal")] }
        var requests: [[URL]] = []
        environment.openURLs = { urls, target, configuration, _ in
            requests.append(urls)
            XCTAssertEqual(target, fallbackURL)
            XCTAssertTrue(configuration.arguments.isEmpty)
        }
        let outcome = Dispatcher(fallbackApp: "fallback", environment: environment)
            .openInBrowser(bundleID: "chrome", profile: "Work", urls: urls)
        XCTAssertEqual(requests, [urls])
        if case .degradedToFallback = outcome {} else { XCTFail("Expected degraded result") }
    }

    /// With no browser to fall back to, opening Chrome anyway would land in its last-used profile.
    func testMissingProfileAsksWhenThePickerIsTheFallback() {
        var environment = environment()
        environment.family = { _ in .chromium }
        environment.chromiumProfiles = { _ in [BrowserProfile(directory: "Default", displayName: "Personal")] }
        let outcome = Dispatcher(fallbackApp: Fallback.picker, environment: environment)
            .openInBrowser(bundleID: "chrome", profile: "Work", urls: urls)
        if case .needsPicker = outcome {} else { XCTFail("Expected the picker") }
    }

    /// When Chrome is the fallback, Junction can't go through the system default: that's Junction.
    func testMissingProfileInTheFallbackBrowserOpensItWithoutAProfile() {
        var environment = environment()
        environment.family = { _ in .chromium }
        environment.chromiumProfiles = { _ in [BrowserProfile(directory: "Default", displayName: "Personal")] }
        var requests: [[URL]] = []
        environment.openURLs = { urls, _, _, _ in requests.append(urls) }
        let outcome = Dispatcher(fallbackApp: "chrome", environment: environment)
            .openInBrowser(bundleID: "chrome", profile: "Work", urls: urls)
        XCTAssertEqual(requests, [urls])
        if case .degradedToFallback = outcome {} else { XCTFail("Expected degraded result") }
    }

    /// Without Full Disk Access the list comes back empty: rules written as directories keep
    /// working, and a synced name can't be mistaken for one.
    func testUnreadableChromiumProfileList() {
        XCTAssertEqual([BrowserProfile]().launchDirectory(for: "Profile 2"), "Profile 2")
        XCTAssertEqual([BrowserProfile]().launchDirectory(for: "Default"), "Default")
        XCTAssertNil([BrowserProfile]().launchDirectory(for: "Work"))
    }

    func testRuleValuePrefersTheNameUnlessItIsAmbiguous() {
        let work = BrowserProfile(directory: "Profile 1", displayName: "Work")
        let twin = BrowserProfile(directory: "Profile 2", displayName: "Twin")
        let otherTwin = BrowserProfile(directory: "Profile 3", displayName: "Twin")
        let profiles = [work, twin, otherTwin]
        XCTAssertEqual(profiles.ruleValue(for: work), "Work")
        XCTAssertEqual(profiles.ruleValue(for: otherTwin), "Profile 3")
        XCTAssertEqual(profiles.matching("Profile 3"), otherTwin)
    }

    func testNativeFailureReachesCompletionAfterInitiation() {
        var environment = environment()
        var nativeCompletion: (@Sendable (BrowserBatchOutcome) -> Void)?
        environment.openURLs = { _, _, _, completion in nativeCompletion = completion }
        let completed = expectation(description: "native failure")
        let immediate = Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "test.browser", profile: nil, urls: urls) { result in
                guard case .failed(let reason) = result else { return XCTFail("Expected failure") }
                XCTAssertEqual(reason, "test failure")
                completed.fulfill()
            }
        if case .opened = immediate {} else { XCTFail("Expected initiated launch") }
        nativeCompletion?(.failed("test failure"))
        wait(for: [completed], timeout: 1)
    }

    func testEmptyBatchCompletesOnceWithoutLaunching() {
        var environment = environment()
        environment.applicationURL = { _ in XCTFail("Empty batch must not resolve a browser"); return nil }
        let completed = expectation(description: "empty batch")
        completed.assertForOverFulfill = true
        Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "test.browser", profile: nil, urls: []) { outcome in
                if case .opened = outcome {} else { XCTFail("Expected successful no-op") }
                completed.fulfill()
            }
        wait(for: [completed], timeout: 1)
    }

    func testSingleURLWrapperPreservesRetryURL() {
        var environment = environment()
        environment.applicationURL = { _ in nil }
        let url = urls[0]
        let completed = expectation(description: "single URL callback")
        let immediate = Dispatcher(fallbackApp: "picker", environment: environment)
            .openInBrowser(bundleID: "missing", profile: nil, url: url) { result in
                guard case .needsPicker(let retry) = result else { return XCTFail("Expected retry") }
                XCTAssertEqual(retry, url)
                completed.fulfill()
            }
        if case .needsPicker(let retry) = immediate { XCTAssertEqual(retry, url) }
        else { XCTFail("Expected immediate single-URL retry") }
        wait(for: [completed], timeout: 1)
    }

    /// A Chrome app shim on disk, as Chrome writes it, for the real Info.plist reader.
    private func webAppShim() throws -> URL {
        let shim = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Mail.app")
        let contents = shim.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: NSDictionary = [
            "CFBundleIdentifier": "pwa",
            "CrAppModeShortcutID": "abcdefghijklmnop",
            "CrAppModeShortcutName": "Mail",
            "CrAppModeShortcutURL": "https://example.com/",
            "CrBundleIdentifier": "chrome",
        ]
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        addTeardownBlock { try? FileManager.default.removeItem(at: shim.deletingLastPathComponent()) }
        return shim
    }

    func testWebAppLaunchesItsBrowserOncePerURL() throws {
        let shim = try webAppShim()
        for (ruleProfile, expected) in [(nil, "Profile 1"), ("Work", "Work")] {
            var environment = environment()
            environment.applicationURL = { $0 == "pwa" ? shim : self.appURL }
            environment.webApp = { ChromiumWebApp(appURL: $0) }
            environment.webAppProfile = { _ in "Profile 1" }
            var launches: [[String]] = []
            environment.openApplication = { target, configuration, _ in
                XCTAssertEqual(target, self.appURL)
                XCTAssertTrue(configuration.createsNewApplicationInstance)
                launches.append(configuration.arguments)
            }
            let outcome = Dispatcher(fallbackApp: "fallback", environment: environment)
                .openInBrowser(bundleID: "pwa", profile: ruleProfile, urls: urls)
            XCTAssertEqual(launches, urls.map {
                ["--profile-directory=\(expected)", "--app-id=abcdefghijklmnop",
                 "--app-launch-url-for-shortcuts-menu-item=\($0.absoluteString)"]
            })
            if case .opened = outcome {} else { XCTFail("Expected opened") }
        }
    }

    func testWebAppSendsWholeBatchToFallbackWhenItCannotOpenIt() throws {
        let shim = try webAppShim()
        let fallbackURL = URL(fileURLWithPath: "/Applications/Fallback.app")
        let outside = urls + [URL(string: "https://other.com/")!]
        for (batch, profile) in [(outside, "Profile 1"), (urls, nil)] {
            var environment = environment()
            environment.applicationURL = { $0 == "pwa" ? shim : $0 == "fallback" ? fallbackURL : self.appURL }
            environment.webApp = { ChromiumWebApp(appURL: $0) }
            environment.webAppProfile = { _ in profile }
            var requests: [[URL]] = []
            environment.openURLs = { urls, target, _, _ in
                XCTAssertEqual(target, fallbackURL)
                requests.append(urls)
            }
            let outcome = Dispatcher(fallbackApp: "fallback", environment: environment)
                .openInBrowser(bundleID: "pwa", profile: nil, urls: batch)
            XCTAssertEqual(requests, [batch])
            if case .degradedToFallback = outcome {} else { XCTFail("Expected degraded result") }
        }
    }
}
#endif
