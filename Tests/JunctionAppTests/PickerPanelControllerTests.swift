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
            open: { _, _ in },
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
        var opened: [URL] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { url, _ in opened.append(url) },
            copy: { _ in }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        controller.show(for: firstURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.pick(browserChoice, sessionID: sessionID)

        XCTAssertEqual(opened, [firstURL, secondURL, firstURL])
        XCTAssertNil(controller.session)
    }

    func testCopyUsesEveryURLSeparatedByNewlines() throws {
        let browserChoice = choice()
        var copied: [String] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _ in },
            copy: { copied.append($0) }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let sessionID = try XCTUnwrap(controller.session?.id)
        controller.copy(sessionID: sessionID)

        XCTAssertEqual(copied, ["\(firstURL.absoluteString)\n\(secondURL.absoluteString)"])
        XCTAssertNil(controller.session)
    }

    func testCancelClearsTheDisplayedBatch() throws {
        let browserChoice = choice()
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _ in },
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
            open: { _, _ in },
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
            open: { _, _ in },
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
            open: { _, _ in },
            copy: { _ in }
        )
        controller.show(for: firstURL)
        let staleSessionID = try XCTUnwrap(controller.session?.id)
        let stalePanel = panel()
        controller.installPanelForTesting(stalePanel)
        controller.cancel(sessionID: staleSessionID)

        controller.show(for: secondURL)
        let replacementID = try XCTUnwrap(controller.session?.id)
        controller.cancel(sessionID: staleSessionID)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: stalePanel))

        XCTAssertEqual(controller.session?.id, replacementID)
    }

    func testSynchronousRetrySurvivesAndPresentsAfterWholeSnapshotDispatch() throws {
        let browserChoice = choice()
        var opened: [URL] = []
        var presentedIDs: [UUID] = []
        var controller: PickerPanelController!
        controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { url, _ in
                opened.append(url)
                if opened.count == 1 {
                    controller.show(for: self.retryURL)
                    XCTAssertNil(controller.session)
                    XCTAssertEqual(presentedIDs.count, 1)
                }
            },
            copy: { _ in },
            presentsPanel: true,
            presentSession: { session, _ in presentedIDs.append(session.id) }
        )

        controller.show(for: firstURL)
        controller.show(for: secondURL)
        let originalID = try XCTUnwrap(controller.session?.id)
        controller.pick(browserChoice, sessionID: originalID)

        XCTAssertEqual(opened, [firstURL, secondURL])
        XCTAssertEqual(presentedIDs.count, 2)
        XCTAssertNotEqual(controller.session?.id, originalID)
        XCTAssertEqual(controller.session?.urls, [retryURL])
        XCTAssertEqual(presentedIDs.last, controller.session?.id)
    }

    func testCreateRuleConsumesOnlyASingleLink() throws {
        let browserChoice = choice()
        var ruleURLs: [URL] = []
        let controller = PickerPanelController(
            choices: { [browserChoice] },
            open: { _, _ in },
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
            open: { _, _ in XCTFail("No choice should be opened") },
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
        var controller: PickerPanelController!
        controller = PickerPanelController(
            choices: { browsersRemain ? [browserChoice] : [] },
            open: { url, _ in controller.show(for: url) },
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
        controller = nil
    }

}
#endif
