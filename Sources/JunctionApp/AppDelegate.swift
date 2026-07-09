#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var state: AppState!
    private var statusItem: StatusItemController!
    private var picker: PickerPanelController!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
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
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state?.configStore.stopWatching()
        return .terminateNow
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
