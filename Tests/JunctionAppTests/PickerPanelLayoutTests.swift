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

    private func settle() async throws {
        // Allow SwiftUI to update its hosted view and the queued first-responder/layout work.
        for _ in 0..<5 { try await Task.sleep(nanoseconds: 10_000_000) }
    }

    private func key(_ code: UInt16, in panel: NSPanel, flags: NSEvent.ModifierFlags = [], text: String = "") throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code
        ))
        let responder = try XCTUnwrap(panel.firstResponder)
        XCTAssertTrue(responder is NSView, "The hosted keyboard view must own first responder")
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
        try await settle()
        XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(panel.frame))

        controller.show(for: second)
        for index in 0..<40 { controller.show(for: URL(string: "https://example.com/\(index)")!) }
        try await settle()
        XCTAssertTrue(controller.panel === panel)
        XCTAssertEqual(controller.session?.id, sessionID)
        XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(panel.frame))
        let batch = try XCTUnwrap(controller.session?.urls)

        for _ in 0..<20 { try key(125, in: panel) }
        try await settle()
        // PickerView declares the URL preview first and browser viewport second.
        // Do not choose by document size: a long URL list can be the larger document.
        let viewports = scrollViews(in: try XCTUnwrap(panel.contentView))
        XCTAssertEqual(viewports.count, 2)
        let browserViewport = try XCTUnwrap(viewports.last)
        let browserDocument = try XCTUnwrap(browserViewport.documentView)
        XCTAssertEqual(browserDocument.bounds.height, CGFloat(browserChoices.count) * 34 - 2, accuracy: 1)
        XCTAssertGreaterThanOrEqual(browserViewport.documentVisibleRect.maxY, browserDocument.bounds.maxY - 1,
                                    "The final browser row must be visible before Return")
        XCTAssertLessThanOrEqual(browserViewport.documentVisibleRect.minY, browserDocument.bounds.maxY - 32,
                                 "The entire final browser row must fit in the viewport")
        let arrivingAfterNavigation = URL(string: "https://example.com/after-navigation")!
        controller.show(for: arrivingAfterNavigation)
        try await settle()
        XCTAssertEqual(controller.session?.id, sessionID)
        try key(36, in: panel)
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
        try await settle()
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertLessThan(panel.frame.height, 260, "Ordinary pickers should stay compact")
        try key(8, in: panel, flags: .command, text: "c")
        XCTAssertEqual(copied, ["\(first.absoluteString)\n\(second.absoluteString)"])
        XCTAssertNil(controller.session)

        controller.show(for: first)
        controller.show(for: second)
        try await settle()
        try key(53, in: XCTUnwrap(controller.panel))
        XCTAssertNil(controller.session)
        XCTAssertEqual(copied.count, 1)
    }
}
#endif
