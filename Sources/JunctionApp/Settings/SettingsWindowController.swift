#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

/// Standard macOS Settings window: toolbar-style tabs (like Safari/Mail preferences),
/// SF Symbol per pane, window title follows the selected pane.
@MainActor
final class SettingsWindowController: NSObject {
    private let state: AppState
    private var window: NSWindow?
    private var tabController: NSTabViewController?

    init(state: AppState) {
        self.state = state
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(jumpToRules),
            name: .junctionPrefillRule,
            object: nil
        )
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func jumpToRules() {
        show()
        tabController?.selectedTabViewItemIndex = 0
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        // Window title follows the selected pane's title.
        tabs.canPropagateSelectedChildViewControllerTitle = true

        let paneSize = NSSize(width: 700, height: 460)
        func pane(_ title: String, _ symbol: String, _ view: some View) {
            let hosting = NSHostingController(
                rootView: view.frame(
                    minWidth: paneSize.width, maxWidth: paneSize.width,
                    minHeight: paneSize.height, maxHeight: paneSize.height
                )
            )
            hosting.title = title
            // NSTabViewController sizes the window from this — a SwiftUI hosting
            // controller won't derive it from .frame on its own.
            hosting.preferredContentSize = paneSize
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }

        pane("Rules", "list.bullet.rectangle", RulesPane(state: state))
        pane("Browsers", "globe", BrowsersPane(state: state))
        pane("Deep Links", "link", DeepLinksPane(state: state))
        pane("Transforms", "wand.and.stars", TransformsPane(state: state))
        pane("Tester", "checkmark.seal", TesterPane(state: state))
        pane("General", "gearshape", GeneralPane(state: state))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.setContentSize(paneSize) // correct size on first display, before any tab switch
        window.title = "Rules"
        window.isReleasedWhenClosed = false
        window.center()
        tabController = tabs
        return window
    }
}
#endif
