#if canImport(AppKit)
import AppKit
import Combine
import Foundation
import SwiftUI

/// Settings panes, in sidebar order.
enum SettingsPane {
    case general, rules, browsers, deepLinks, transforms, tester, about

    var title: String {
        switch self {
        case .general: return "General"
        case .rules: return "Rules"
        case .browsers: return "Browsers"
        case .deepLinks: return "Deep Links"
        case .transforms: return "Transforms"
        case .tester: return "Tester"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .rules: return "list.bullet"
        case .browsers: return "globe"
        case .deepLinks: return "link"
        case .transforms: return "wand.and.stars"
        case .tester: return "checkmark.seal.fill"
        case .about: return "info"
        }
    }

    var tint: Color {
        switch self {
        case .general, .about: return .gray
        case .rules: return .blue
        case .browsers: return .teal
        case .deepLinks: return .purple
        case .transforms: return .orange
        case .tester: return .green
        }
    }
}

/// Opens the rule editor on a new rule: the toolbar's +, or "Add rule for this link" from the
/// picker or the menu. It's state rather than a notification because the detail column only
/// builds the selected pane, so `RulesPane` may not exist yet when the request arrives.
struct NewRuleRequest {
    let id = UUID()
    var url: URL?
    var sourceApp: String?
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
    @Published var newRule: NewRuleRequest?
}

/// System Settings-style window: a sidebar of panes beside the selected one. AppKit owns the
/// split view and toolbar because SwiftUI can't drive a hosted window's toolbar before macOS 14.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    private static let addRuleItem = NSToolbarItem.Identifier("addRule")

    private let state: AppState
    private let nav = SettingsNavigation()
    private var window: NSWindow?
    private var paneObserver: AnyCancellable?

    init(state: AppState) {
        self.state = state
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(prefillRule(_:)),
            name: .junctionPrefillRule,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showRules),
            name: .junctionShowRules,
            object: nil
        )
    }

    func show() {
        if window == nil {
            let window = makeWindow()
            self.window = window
            paneObserver = nav.$pane.sink { [weak self] pane in self?.update(window, for: pane) }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showRules() {
        nav.pane = .rules
        show()
    }

    @objc private func prefillRule(_ note: Notification) {
        nav.newRule = NewRuleRequest(
            url: note.userInfo?["url"] as? URL,
            sourceApp: note.userInfo?["sourceApp"] as? String
        )
        showRules()
    }

    @objc private func addRule() {
        nav.newRule = NewRuleRequest()
    }

    private func makeWindow() -> NSWindow {
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: hosting(SettingsSidebar(nav: nav)))
        sidebar.canCollapse = false
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 260
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: hosting(SettingsDetail(state: state, nav: nav))))

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 680, height: 440)
        window.setContentSize(NSSize(width: 780, height: 540))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// The hosting controllers mustn't size the window from their SwiftUI content, or it
    /// stops being resizable.
    private func hosting<Content: View>(_ view: Content) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        return controller
    }

    /// The title, subtitle and toolbar follow the selected pane. `NSToolbarItem.isHidden`
    /// needs macOS 15, so the + is inserted and removed instead.
    private func update(_ window: NSWindow, for pane: SettingsPane) {
        window.title = pane.title
        window.subtitle = pane == .rules ? "First matching rule wins. Drag to reorder." : ""
        guard let toolbar = window.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.addRuleItem }
        if pane == .rules, index == nil {
            toolbar.insertItem(withItemIdentifier: Self.addRuleItem, at: toolbar.items.count)
        } else if pane != .rules, let index {
            toolbar.removeItem(at: index)
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, Self.addRuleItem]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.addRuleItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Rule")
        item.label = "Add Rule"
        item.toolTip = "Add a rule"
        item.isBordered = true
        item.target = self
        item.action = #selector(addRule)
        return item
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        // A sidebar can deselect on a click in empty space; keep the current pane instead.
        List(selection: Binding(get: { nav.pane }, set: { if let pane = $0 { nav.pane = pane } })) {
            Section { row(.general) }
            Section("Routing") {
                row(.rules)
                row(.browsers)
                row(.deepLinks)
                row(.transforms)
            }
            Section { row(.tester) }
            Section { row(.about) }
        }
        .listStyle(.sidebar)
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            // Coloured tiles as in System Settings; a sidebar doesn't draw them itself.
            Image(systemName: pane.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .tag(pane)
    }
}

private struct SettingsDetail: View {
    @ObservedObject var state: AppState
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        Group {
            switch nav.pane {
            case .general: GeneralPane(state: state)
            case .rules: RulesPane(state: state, nav: nav)
            case .browsers: BrowsersPane(state: state)
            case .deepLinks: DeepLinksPane(state: state)
            case .transforms: TransformsPane(state: state)
            case .tester: TesterPane(state: state)
            case .about: AboutPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .capsuleButtons()
    }
}
#endif
