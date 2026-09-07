#if canImport(AppKit)
import AppKit
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
}
#endif
