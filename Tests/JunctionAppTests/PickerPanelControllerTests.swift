#if canImport(AppKit)
import AppKit
import Foundation
import XCTest

@testable import JunctionApp
@testable import JunctionMacKit

@MainActor
final class PickerPanelControllerTests: XCTestCase {
    private let firstURL = URL(string: "https://example.com/first")!
    private let secondURL = URL(string: "https://example.com/second")!
    private let retryURL = URL(string: "https://example.com/retry")!

    private func choice() -> PickerPanelController.Choice {
        let browser = Browser(
            bundleID: "com.example.TestBrowser",
            name: "Test Browser",
            appURL: URL(fileURLWithPath: "/Applications/Test Browser.app"),
            profiles: []
        )
        return PickerPanelController.Choice(browser: browser, profile: nil)
    }

    private func panel() -> NSPanel {
        NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    func testAdditionalShowUpdatesTheSameSessionInArrivalOrder() throws {
        let browserChoice = choice()
        var presentations: [PickerPanelController.Session] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { _ in },
            presentsPanel: true,
            presentSession: { session, _ in presentations.append(session) }
        )

        controller.show(for: firstURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.show(for: secondURL)

        XCTAssertEqual(controller.session?.id, sessionID)
        XCTAssertEqual(controller.session?.urls, [firstURL, secondURL])
        XCTAssertEqual(presentations.map(\.id), [sessionID])
    }

    func testPickOpensEveryURLInOrderAndKeepsDuplicates() throws {
        let browserChoice = choice()
        var opened: [[URL]] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { urls, _, completion in opened.append(urls); completion(.opened) },
            copy: { _ in }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        controller.show(for: firstURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.pick(browserChoice, sessionID: sessionID)

        XCTAssertEqual(opened, [[firstURL, secondURL, firstURL]])
        XCTAssertNil(controller.session)
    }

    func testCopyUsesEveryURLSeparatedByNewlines() throws {
        let browserChoice = choice()
        var copied: [String] = []
        var copiedCounts: [Int] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { copied.append($0) },
            copiedConfirmation: { copiedCounts.append($0) }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.copy(sessionID: sessionID)

        XCTAssertEqual(copied, ["\(firstURL.absoluteString)\n\(secondURL.absoluteString)"])
        XCTAssertEqual(copiedCounts, [2])
        XCTAssertNil(controller.session)
    }

    func testCancelClearsTheDisplayedBatch() throws {
        let browserChoice = choice()
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { _ in }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.cancel(sessionID: sessionID)

        XCTAssertNil(controller.session)
    }

    func testFocusBeforeKeyDoesNotCancelTheSession() throws {
        let browserChoice = choice()
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { _ in }
        )
        controller.show(for: firstURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        let panel = panel()
        controller.installPanelForTesting(panel)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))

        XCTAssertEqual(controller.session?.id, sessionID)
    }

    func testFocusAfterKeyCancelsTheSession() throws {
        let browserChoice = choice()
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { _ in }
        )
        controller.show(for: firstURL)
        let panel = panel()
        controller.installPanelForTesting(panel)

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: panel))
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))

        XCTAssertNil(controller.session)
    }

    func testStaleSessionAndPanelCallbacksCannotClearReplacement() throws {
        let browserChoice = choice()
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, _ in XCTFail("A stale choice must not open anything") },
            copy: { _ in XCTFail("A stale copy must not change the clipboard") }
        )
        controller.show(for: firstURL)
        let staleSessionID = try XCTUnwrap(controller.session?.id)
        let stalePanel = panel()
        controller.installPanelForTesting(stalePanel)
        controller.cancel(sessionID: staleSessionID)

        controller.show(for: secondURL)
        let replacementID = try XCTUnwrap(controller.session?.id)
        let replacementPanel = panel()
        controller.installPanelForTesting(replacementPanel)
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: replacementPanel))

        controller.cancel(sessionID: staleSessionID)
        controller.pick(browserChoice, sessionID: staleSessionID)
        controller.copy(sessionID: staleSessionID)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: stalePanel))
        XCTAssertEqual(controller.session?.id, replacementID)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: replacementPanel))
        XCTAssertNil(controller.session, "Focus loss from the current keyed panel must still dismiss it")
    }

    func testRetryWaitsForBatchCompletionAndKeepsNewArrivals() throws {
        let browserChoice = choice()
        var opened: [[URL]] = []
        var presentedIDs: [UUID] = []
        var completion: (@MainActor (BrowserBatchOutcome) -> Void)?
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { urls, _, callback in opened.append(urls); completion = callback },
            copy: { _ in },
            presentsPanel: true,
            presentSession: { session, _ in presentedIDs.append(session.id) }
        )
        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let originalID = try XCTUnwrap(controller.session?.id)
        controller.pick(browserChoice, sessionID: originalID)
        controller.show(for: retryURL)
        XCTAssertNil(controller.session)
        XCTAssertEqual(presentedIDs.count, 1, "No retry window may appear while the native request is pending")

        completion?(.needsPicker)
        XCTAssertEqual(opened, [[firstURL, secondURL]])
        XCTAssertEqual(presentedIDs.count, 2)
        XCTAssertNotEqual(controller.session?.id, originalID)
        XCTAssertEqual(controller.session?.urls, [firstURL, secondURL, retryURL])
        completion?(.needsPicker)
        XCTAssertEqual(presentedIDs.count, 2, "Duplicate completion must not duplicate the batch")
    }

    func testSuccessfulBatchRevealsOnlyNewArrivals() throws {
        let browserChoice = choice()
        var completion: (@MainActor (BrowserBatchOutcome) -> Void)?
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, callback in completion = callback },
            copy: { _ in }
        )
        controller.show(for: firstURL)
        controller.show(for: secondURL)
        controller.pick(browserChoice, sessionID: try XCTUnwrap(controller.session?.id))
        controller.show(for: retryURL)
        completion?(.opened)
        XCTAssertEqual(controller.session?.urls, [retryURL])
        completion?(.failed("late duplicate"))
        XCTAssertEqual(controller.session?.urls, [retryURL])
    }

    func testDelayedFailureRestoresTheEntireBatch() throws {
        let browserChoice = choice()
        var completion: (@MainActor (BrowserBatchOutcome) -> Void)?
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, callback in completion = callback },
            copy: { _ in }
        )
        controller.show(for: firstURL)
        controller.show(for: secondURL)
        controller.show(for: firstURL)
        controller.pick(browserChoice, sessionID: try XCTUnwrap(controller.session?.id))
        XCTAssertNil(controller.session)
        completion?(.failed("Test launch failure"))
        XCTAssertEqual(controller.session?.urls, [firstURL, secondURL, firstURL])
    }

    func testCreateRuleConsumesOnlyASingleLink() throws {
        let browserChoice = choice()
        var ruleURLs: [URL] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _, completion in completion(.opened) },
            copy: { _ in },
            createRule: { ruleURLs.append($0) }
        )
        controller.show(for: firstURL)
        let batchID = try XCTUnwrap(controller.session?.id)
        controller.show(for: secondURL)
        controller.createRule(sessionID: batchID)
        XCTAssertTrue(ruleURLs.isEmpty)
        XCTAssertEqual(controller.session?.urls, [firstURL, secondURL])

        controller.cancel(sessionID: batchID)
        controller.show(for: retryURL)
        let singleID = try XCTUnwrap(controller.session?.id)
        controller.createRule(sessionID: singleID)
        XCTAssertEqual(ruleURLs, [retryURL])
        XCTAssertNil(controller.session)
    }

    func testNoBrowsersUsesFallbackForEachRequest() {
        var fallbackURLs: [URL] = []
        let controller = PickerPanelController(
            choices: { [] },
            open: { _, _, _ in XCTFail("No choice should be opened") },
            copy: { _ in },
            noChoices: { fallbackURLs.append(contentsOf: $0) }
        )
        controller.show(for: firstURL)
        controller.show(for: secondURL)
        XCTAssertEqual(fallbackURLs, [firstURL, secondURL])
        XCTAssertNil(controller.session)
    }

    func testMissingBrowserRetriesReachFallbackAsOneBatch() throws {
        let browserChoice = choice()
        var browsersRemain = true
        var fallbackBatches: [[URL]] = []
        let controller = PickerPanelController(
            choices: { browsersRemain ? [browserChoice] : [] },
            open: { _, _, completion in completion(.needsPicker) },
            copy: { _ in },
            noChoices: { fallbackBatches.append($0) }
        )
        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let originalID = try XCTUnwrap(controller.session?.id)
        browsersRemain = false
        controller.pick(browserChoice, sessionID: originalID)
        XCTAssertEqual(fallbackBatches, [[firstURL, secondURL]])
        XCTAssertNil(controller.session)
    }

}
#endif
