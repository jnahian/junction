#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import SwiftUI

/// First-launch flow (PRD §10): explain → pick fallback → set default → starter rules.
@MainActor
final class OnboardingWindowController {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        // Reuse an open window; a finished (closed) one is recreated so the flow restarts.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(state: state) { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            self?.window?.close()
            self?.window = nil
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Junction"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct StarterTemplate: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let rule: Rule
}

enum StarterTemplates {
    static func load() -> [StarterTemplate] {
        struct FileFormat: Decodable { var templates: [StarterTemplate] }
        guard let url = Bundle.module.url(forResource: "starter-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(FileFormat.self, from: data) else { return [] }
        return parsed.templates
    }
}

private struct OnboardingView: View {
    @ObservedObject var state: AppState
    let onDone: () -> Void

    @State private var step = 0
    @State private var fallbackBundleID: String = "com.apple.Safari"
    @State private var selectedTemplates: Set<String> = []
    private let templates = StarterTemplates.load()

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            switch step {
            case 0: welcome
            case 1: fallbackPicker
            case 2: defaultBrowser
            default: starterRules
            }
            Spacer()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Spacer()
                Button(step == 3 ? "Finish" : "Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.windowPadding)
        .padding(.top, Metrics.controlSpacing) // clear the (transparent) titlebar
        .frame(width: 480, height: 420)
        .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            HStack(spacing: Metrics.sectionSpacing) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.blue, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Junction").font(.largeTitle.bold())
                    Text("Every link, in the right place")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, Metrics.controlSpacing)
            Text("""
            Junction becomes your default browser — but it never shows a window. \
            When you click a link anywhere, Junction checks your rules and instantly \
            hands the link to the right browser, browser profile, or native app.

            Rules live in a plain JSON file you can edit, version, and sync — \
            or manage entirely from this app. No telemetry, ever.
            """)
        }
    }

    private var fallbackPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your fallback browser").font(.title2.bold())
            Text("Any link that doesn't match a rule opens here. You can change this anytime.")
                .foregroundStyle(.secondary)
            Picker("Fallback browser", selection: $fallbackBundleID) {
                ForEach(state.browsers) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .onAppear {
            state.refreshBrowsers()
            if let first = state.browsers.first(where: { $0.bundleID == "com.apple.Safari" }) ?? state.browsers.first {
                fallbackBundleID = first.bundleID
            }
        }
    }

    private var defaultBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make Junction your default browser").font(.title2.bold())
            Text("macOS will ask you to confirm. This is how Junction sees every clicked link.")
                .foregroundStyle(.secondary)
            Button("Set Junction as Default Browser…") {
                state.requestDefaultBrowser()
            }
            if state.isDefaultBrowser {
                Label("Junction is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var starterRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starter rules").font(.title2.bold())
            Text("Pick any that fit — edit them later in Settings.")
                .foregroundStyle(.secondary)
            ForEach(templates) { template in
                Toggle(isOn: Binding(
                    get: { selectedTemplates.contains(template.id) },
                    set: { on in
                        if on { selectedTemplates.insert(template.id) } else { selectedTemplates.remove(template.id) }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(template.title)
                        Text(template.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func advance() {
        if step < 3 {
            step += 1
            return
        }
        state.updateConfig { config in
            config.fallback.app = fallbackBundleID
            let chosen = templates.filter { selectedTemplates.contains($0.id) }.map(\.rule)
            // Skip templates already present (re-running the tour must not duplicate rules).
            config.rules.append(contentsOf: chosen.filter { rule in !config.rules.contains(rule) })
        }
        onDone()
    }
}
#endif
