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

        // Here, not in the menu: it's only built on open, so checks wouldn't start until
        // the user first opened it.
        updateChecker.start()

        state.$configError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        state.$isDefaultBrowser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateChecker.$available
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    /// Template rendition of the app icon (three-way branch), shipped as an SVG resource.
    private static let branchIcon: NSImage? = {
        guard let url = CoreResources.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    /// Same icon with a dot in the corner. Menu bar images must stay template (the system
    /// tints them for light/dark), so the badge is a shape punched out of the icon, not a color.
    private static let branchIconWithUpdateDot: NSImage? = {
        guard let base = branchIcon else { return nil }
        let badged = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = true
        return badged
    }()

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image: NSImage?
        if state.configError != nil {
            // invalid config → warning badge (PRD §6.1)
            let base = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Junction")
            image = base?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? base
            image?.isTemplate = true
        } else {
            image = updateChecker.available == nil ? Self.branchIcon : Self.branchIconWithUpdateDot
        }
        button.image = image
        // dimmed = gentle "not active" state (PRD §11)
        button.appearsDisabled = !state.isDefaultBrowser && state.configError == nil
    }

    // Rebuild the menu each time it opens so recent links are fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refreshDefaultBrowserStatus()
        menu.removeAllItems()

        if let error = state.configError {
            let item = NSMenuItem(title: "Config File Is Invalid", action: #selector(showConfigError), keyEquivalent: "")
                .withSymbol("exclamationmark.triangle.fill")
            item.target = self
            item.toolTip = error.description
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if !state.isDefaultBrowser {
            let item = NSMenuItem(title: "Junction Is Not the Default Browser", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let enable = NSMenuItem(title: "Set as Default Browser…", action: #selector(setDefault), keyEquivalent: "")
                .withSymbol("checkmark.seal")
            enable.target = self
            menu.addItem(enable)
            menu.addItem(.separator())
        }

        let pause = NSMenuItem(
            title: state.routingPaused ? "Resume Routing" : "Pause Routing",
            action: #selector(togglePause),
            keyEquivalent: ""
        ).withSymbol(state.routingPaused ? "play.circle" : "pause.circle")
        pause.target = self
        if !state.routingPaused { pause.toolTip = "Send every link to the fallback browser" }
        menu.addItem(pause)
        menu.addItem(.separator())

        // Recent links (in-memory only) nest under one item, each with "create rule from
        // this" (F3) a level deeper.
        let recent = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
            .withSymbol("clock.arrow.circlepath")
        let recentMenu = NSMenu()
        if state.recentLinks.isEmpty {
            let empty = NSMenuItem(title: "No links routed yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for link in state.recentLinks {
                let title = link.url.absoluteString.count > 60
                    ? String(link.url.absoluteString.prefix(57)) + "…"
                    : link.url.absoluteString
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.toolTip = "\(link.url.absoluteString)\nSource: \(link.sourceApp ?? "unknown")\n→ \(link.outcome)"

                let actions = NSMenu()
                let addRule = NSMenuItem(title: "Create Rule from This Link…", action: #selector(createRule(_:)), keyEquivalent: "")
                    .withSymbol("plus.circle")
                addRule.target = self
                addRule.representedObject = link
                actions.addItem(addRule)
                let copy = NSMenuItem(title: "Copy URL", action: #selector(copyURL(_:)), keyEquivalent: "")
                    .withSymbol("doc.on.doc")
                copy.target = self
                copy.representedObject = link
                actions.addItem(copy)
                item.submenu = actions
                recentMenu.addItem(item)
            }
        }
        recent.submenu = recentMenu
        menu.addItem(recent)

        // Rules, in match order, each a checkmark toggle for `enabled`.
        let rules = NSMenuItem(title: "Rules", action: nil, keyEquivalent: "")
            .withSymbol("list.bullet")
        let rulesMenu = NSMenu()
        if state.config.rules.isEmpty {
            let empty = NSMenuItem(title: "No rules yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            rulesMenu.addItem(empty)
        }
        for (index, rule) in state.config.rules.enumerated() {
            let item = NSMenuItem(title: rule.name, action: #selector(toggleRule(_:)), keyEquivalent: "")
            item.target = self
            item.state = rule.enabled ? .on : .off
            item.representedObject = RuleRef(index: index, name: rule.name)
            item.toolTip = rule.enabled ? "Click to turn this rule off" : "Click to turn this rule on"
            rulesMenu.addItem(item)
        }
        rulesMenu.addItem(.separator())
        let editRules = NSMenuItem(title: "Edit Rules…", action: #selector(showRules), keyEquivalent: "")
        editRules.target = self
        rulesMenu.addItem(editRules)
        rules.submenu = rulesMenu
        menu.addItem(rules)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .withSymbol("gearshape")
        settings.target = self
        menu.addItem(settings)
        if updateChecker.currentVersion != nil {
            let pending = updateChecker.available
            let update = NSMenuItem(
                title: pending.map { "Update to \($0.version)…" } ?? "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            ).withSymbol(pending == nil ? "arrow.down.circle" : "arrow.down.circle.fill")
            update.target = self
            menu.addItem(update)
        }
        let quit = NSMenuItem(title: "Quit Junction", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func togglePause() { state.routingPaused.toggle() }

    /// Position plus name: rule ids aren't persisted, and the file can change while the menu
    /// is open, so only toggle if the rule at that position is still the one that was shown.
    private struct RuleRef {
        let index: Int
        let name: String
    }

    @objc private func toggleRule(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RuleRef,
              state.config.rules.indices.contains(ref.index),
              state.config.rules[ref.index].name == ref.name else { return }
        state.updateConfig { $0.rules[ref.index].enabled.toggle() }
    }

    @objc private func showRules() {
        NotificationCenter.default.post(name: .junctionShowRules, object: nil)
    }

    /// With an update found, straight to its release page; otherwise check now.
    @objc private func checkForUpdates() {
        if let release = updateChecker.available {
            NSWorkspace.shared.open(release.htmlURL)
        } else {
            updateChecker.checkNow()
        }
    }
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
    static let junctionShowRules = Notification.Name("junctionShowRules")
}
#endif
