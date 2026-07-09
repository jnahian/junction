#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsRootView(state: state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Junction Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRootView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = "rules"

    var body: some View {
        TabView(selection: $selectedTab) {
            RulesPane(state: state)
                .tabItem { Label("Rules", systemImage: "list.bullet") }
                .tag("rules")
            BrowsersPane(state: state)
                .tabItem { Label("Browsers", systemImage: "safari") }
                .tag("browsers")
            DeepLinksPane(state: state)
                .tabItem { Label("Deep Links", systemImage: "app.connected.to.app.below.fill") }
                .tag("deeplinks")
            TransformsPane(state: state)
                .tabItem { Label("Transforms", systemImage: "wand.and.rays") }
                .tag("transforms")
            TesterPane(state: state)
                .tabItem { Label("Tester", systemImage: "checkmark.seal") }
                .tag("tester")
            GeneralPane(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
        }
        .frame(minWidth: 700, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: .junctionPrefillRule)) { _ in
            selectedTab = "rules"
        }
    }
}
#endif
