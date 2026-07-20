#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var state: AppState!
    private var statusItem: StatusItemController!
    private var picker: PickerPanelController!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        // State must exist before the URL handler is registered: when the app is
        // *launched by* opening a link, kAEGetURL arrives before didFinishLaunching.
        state = AppState()
        picker = PickerPanelController(state: state)
        state.pickerPresenter = { [weak self] url in self?.picker.show(for: url) }
        settingsWindow = SettingsWindowController(state: state)
        state.settingsPresenter = { [weak self] in self?.settingsWindow.show() }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(state: state)

        state.onboardingPresenter = { [weak self] in
            guard let self else { return }
            if self.onboardingWindow == nil {
                self.onboardingWindow = OnboardingWindowController(state: self.state)
            }
            self.onboardingWindow?.show()
        }
        if !UserDefaults.standard.bool(forKey: "onboardingComplete") {
            state.onboardingPresenter?()
        }
        state.configStore.bootstrapIfMissing()
        state.configStore.startWatching()

        // A copy run from outside /Applications (a dev build, a Downloads copy) may have
        // registered itself as a login item — as a bare executable it launches into Terminal
        // at startup. Self-heal: drop that registration so only the /Applications install stays.
        if !SMAppService.mainAppCanRegister, SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state?.configStore.stopWatching()
        return .terminateNow
    }

    // MARK: Main menu

    /// An accessory app shows no menu bar, but AppKit still routes key equivalents
    /// through the main menu — without one, ⌘X/⌘C/⌘V and ⌘W do nothing anywhere.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        // First submenu is the app menu; ⌘Q lives here.
        let app = NSMenu()
        app.addItem(withTitle: "Quit Junction", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.setSubmenu(app, for: main.addItem(withTitle: "Junction", action: nil, keyEquivalent: ""))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.setSubmenu(edit, for: main.addItem(withTitle: "Edit", action: nil, keyEquivalent: ""))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.setSubmenu(window, for: main.addItem(withTitle: "Window", action: nil, keyEquivalent: ""))

        return main
    }

    /// Local .html files land here (Finder open / drop on the icon). They have no host, so no
    /// rule could match them — hand them straight to the fallback browser.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            state.openInFallback(URL(fileURLWithPath: path))
        }
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: URL interception (F1)

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              urlString.utf8.count <= 32 * 1024, // cap huge URLs (PRD §11)
              let url = URL(string: urlString) else { return }

        // Non-http(s) schemes occasionally get sent our way — pass through untouched.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            NSWorkspace.shared.open(url)
            return
        }

        // Source app: sender PID attribute → bundle ID (walking Electron helper parents).
        var sourceApp: String? = nil
        if let pidDescriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) {
            let pid = pidDescriptor.int32Value
            if pid > 0 { sourceApp = SourceAppResolver.bundleID(forPID: pid_t(pid)) }
        }

        // ⌥ Option held → force the picker (escape hatch, F7).
        let forcePicker = NSEvent.modifierFlags.contains(.option)

        state.handle(LinkEvent(url: url, sourceApp: sourceApp, forcePicker: forcePicker))
    }
}
#endif
