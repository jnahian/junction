#if canImport(AppKit)
import AppKit

// Top-level code runs on the main thread; assert main-actor isolation for the
// @MainActor-annotated delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate // NSApplication.delegate is unowned; `delegate` lives until run() returns
    app.setActivationPolicy(.accessory) // menu bar only; Info.plist also sets LSUIElement
    app.run()
}
#endif
