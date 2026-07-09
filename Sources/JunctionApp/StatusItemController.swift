#if canImport(AppKit)
import AppKit
import Combine
import Foundation
import JunctionCore

/// Menu bar presence: status, recent links, quick actions (F3 affordance lives here).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        state.$configError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        state.$isDefaultBrowser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if state.configError != nil {
            symbol = "exclamationmark.triangle" // invalid config → warning badge (PRD §6.1)
        } else if !state.isDefaultBrowser {
            symbol = "arrow.triangle.branch" // gentle "not active" state (PRD §11)
        } else {
            symbol = "arrow.triangle.branch"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Junction")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !state.isDefaultBrowser && state.configError == nil
    }

    // Rebuild the menu each time it opens so recent links are fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refreshDefaultBrowserStatus()
        menu.removeAllItems()

        if let error = state.configError {
            let item = NSMenuItem(title: "⚠️ Config file is invalid", action: #selector(showConfigError), keyEquivalent: "")
            item.target = self
            item.toolTip = error.description
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if !state.isDefaultBrowser {
            let item = NSMenuItem(title: "Junction is not the default browser", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let enable = NSMenuItem(title: "Set as Default Browser…", action: #selector(setDefault), keyEquivalent: "")
            enable.target = self
            menu.addItem(enable)
            menu.addItem(.separator())
        }

        let pause = NSMenuItem(
            title: state.routingPaused ? "Resume Routing" : "Pause Routing (use fallback)",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())

        // Recent links (in-memory only), each with "create rule from this" (F3).
        let header = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if state.recentLinks.isEmpty {
            let empty = NSMenuItem(title: "No links routed yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for link in state.recentLinks {
                let title = link.url.absoluteString.count > 60
                    ? String(link.url.absoluteString.prefix(57)) + "…"
                    : link.url.absoluteString
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.toolTip = "\(link.url.absoluteString)\nSource: \(link.sourceApp ?? "unknown")\n→ \(link.outcome)"

                let submenu = NSMenu()
                let addRule = NSMenuItem(title: "Create Rule from This Link…", action: #selector(createRule(_:)), keyEquivalent: "")
                addRule.target = self
                addRule.representedObject = link
                submenu.addItem(addRule)
                let copy = NSMenuItem(title: "Copy URL", action: #selector(copyURL(_:)), keyEquivalent: "")
                copy.target = self
                copy.representedObject = link
                submenu.addItem(copy)
                item.submenu = submenu
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Junction", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func togglePause() { state.routingPaused.toggle() }
    @objc private func setDefault() { state.requestDefaultBrowser() }
    @objc private func openSettings() { state.settingsPresenter?() }

    @objc private func showConfigError() {
        guard let error = state.configError else { return }
        let alert = NSAlert()
        alert.messageText = "Config file is invalid"
        alert.informativeText = error.description + "\n\nJunction keeps using the last valid rules until the file is fixed."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func createRule(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? RecentLink else { return }
        state.settingsPresenter?()
        NotificationCenter.default.post(
            name: .junctionPrefillRule,
            object: nil,
            userInfo: ["url": link.url, "sourceApp": link.sourceApp as Any]
        )
    }

    @objc private func copyURL(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? RecentLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
    }
}

extension Notification.Name {
    static let junctionPrefillRule = Notification.Name("junctionPrefillRule")
}
#endif
