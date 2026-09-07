#if canImport(AppKit)
import AppKit
import XCTest
@testable import JunctionApp
@testable import JunctionMacKit

@MainActor
final class PickerPanelLayoutTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 108, width: 1512, height: 841)
    private let first = URL(string: "https://example.com/first")!
    private let second = URL(string: "https://example.com/second")!

    private func choices(_ count: Int) -> [PickerPanelController.Choice] {
        (0..<count).map { index in
            PickerPanelController.Choice(
                browser: Browser(bundleID: "test.browser.\(index)", name: "Browser \(index)",
                                 appURL: URL(fileURLWithPath: "/Applications/Test.app"), profiles: []),
                profile: nil
            )
        }
    }

    /// Polls rather than sleeping a fixed budget: SwiftUI's hosted layout and the queued
    /// first-responder work can take far longer than a fixed wait on a loaded CI runner.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                return XCTFail("Timed out waiting for \(description)", file: file, line: line)
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func settled(_ panel: NSPanel) -> Bool {
        panel.frame.height > 0 && screen.insetBy(dx: 8, dy: 8).contains(panel.frame)
    }

    private func key(
        _ code: UInt16, in panel: NSPanel, flags: NSEvent.ModifierFlags = [], text: String = ""
    ) async throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code
        ))
        try await waitUntil("the hosted keyboard view to own first responder") {
            panel.firstResponder is NSView
        }
        let responder = try XCTUnwrap(panel.firstResponder)
        responder.keyDown(with: event)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    func testManyChoicesAndLinksStayWithinScreenAndKeyboardReachesLastBrowser() async throws {
        let browserChoices = choices(21)
        var opened: [([URL], String)] = []
        let controller = PickerPanelController(
            choices: { browserChoices },
            open: { urls, choice, completion in
                opened.append((urls, choice.browser.bundleID)); completion(.opened)
            },
            copy: { _ in }, presentsPanel: true, presentSession: { _, _ in },
            visibleFrame: { _ in self.screen }
        )
        defer { controller.dismiss() }
        controller.show(for: first)
        let sessionID = try XCTUnwrap(controller.session?.id)
        let panel = try XCTUnwrap(controller.panel)
        try await waitUntil("the panel to be laid out inside the screen") { self.settled(panel) }

        controller.show(for: second)
        for index in 0..<40 { controller.show(for: URL(string: "https://example.com/\(index)")!) }
        try await waitUntil("the grown panel to stay inside the screen") { self.settled(panel) }
        XCTAssertTrue(controller.panel === panel)
        XCTAssertEqual(controller.session?.id, sessionID)
        let batch = try XCTUnwrap(controller.session?.urls)

        for _ in 0..<20 { try await key(125, in: panel) }
        // PickerView declares the URL preview first and browser viewport second.
        // Do not choose by document size: a long URL list can be the larger document.
        try await waitUntil("both scroll viewports to exist") {
            (try? self.scrollViews(in: XCTUnwrap(panel.contentView)))?.count == 2
        }
        let viewports = scrollViews(in: try XCTUnwrap(panel.contentView))
        let browserViewport = try XCTUnwrap(viewports.last)
        let browserDocument = try XCTUnwrap(browserViewport.documentView)
        XCTAssertEqual(browserDocument.bounds.height, CGFloat(browserChoices.count) * 34 - 2, accuracy: 1)
        try await waitUntil("the final browser row to scroll into view") {
            browserViewport.documentVisibleRect.maxY >= browserDocument.bounds.maxY - 1
        }
        XCTAssertLessThanOrEqual(browserViewport.documentVisibleRect.minY, browserDocument.bounds.maxY - 32,
                                 "The entire final browser row must fit in the viewport")
        let arrivingAfterNavigation = URL(string: "https://example.com/after-navigation")!
        controller.show(for: arrivingAfterNavigation)
        try await waitUntil("the panel to settle after the late arrival") { self.settled(panel) }
        XCTAssertEqual(controller.session?.id, sessionID)
        try await key(36, in: panel)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.0, batch + [arrivingAfterNavigation])
        XCTAssertEqual(opened.first?.1, browserChoices.last?.browser.bundleID)
    }

    func testHostedCopyUsesAppendedLinksAndEscapeCancels() async throws {
        let browserChoices = choices(2)
        var copied: [String] = []
        let controller = PickerPanelController(
            choices: { browserChoices }, open: { _, _, _ in XCTFail("Must not open on copy or Escape") },
            copy: { copied.append($0) }, presentsPanel: true, presentSession: { _, _ in },
            visibleFrame: { _ in self.screen }
        )
        defer { controller.dismiss() }
        controller.show(for: first)
        controller.show(for: second)
        let panel = try XCTUnwrap(controller.panel)
        try await waitUntil("the panel to be laid out inside the screen") { self.settled(panel) }
        XCTAssertLessThan(panel.frame.height, 260, "Ordinary pickers should stay compact")
        try await key(8, in: panel, flags: .command, text: "c")
        XCTAssertEqual(copied, ["\(first.absoluteString)\n\(second.absoluteString)"])
        XCTAssertNil(controller.session)

        controller.show(for: first)
        controller.show(for: second)
        let reopened = try XCTUnwrap(controller.panel)
        try await waitUntil("the reopened panel to be laid out") { self.settled(reopened) }
        try await key(53, in: reopened)
        XCTAssertNil(controller.session)
        XCTAssertEqual(copied.count, 1)
    }
}
#endif
