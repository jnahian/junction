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

    private static let rewriters = RewriterStore.builtin()
    private static let stepCount = 4
    private var isLastStep: Bool { step == Self.stepCount - 1 }
    /// Step 2 is the only one Junction can't work without, so name the opt-out instead of
    /// letting "Continue" quietly mean "no".
    private var isSkippingDefaultBrowser: Bool { step == 2 && !state.isDefaultBrowser }

    /// Templates naming an app the user doesn't have would create rules that can never dispatch,
    /// so don't offer them. Browsers are matched by bundle ID; deep links by whether anything
    /// installed claims the rewriter's URL scheme.
    private var availableTemplates: [StarterTemplate] {
        templates.filter { template in
            switch template.rule.action {
            case .open(let app, _):
                return state.browsers.contains { $0.bundleID == app }
            case .deepLink(let id):
                guard let scheme = Self.rewriters.rewriter(id: id)?.scheme else { return false }
                return BrowserDiscovery.isSchemeHandled(scheme)
            case .prompt, .clipboard:
                return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            // Scrolls so the step content can't clip the buttons at large accessibility text
            // sizes, or when more starter rules are added.
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    switch step {
                    case 0: welcome
                    case 1: fallbackPicker
                    case 2: defaultBrowser
                    default: starterRules
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Spacer()
                stepIndicator
                Spacer()
                if isSkippingDefaultBrowser {
                    // Not the prominent action here — "Set as Default Browser…" is.
                    Button("Skip for now") { advance() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(isLastStep ? "Finish" : "Continue") { advance() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Metrics.windowPadding)
        .padding(.top, Metrics.controlSpacing) // clear the (transparent) titlebar
        .frame(width: 480, height: 420)
        .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
    }

    /// Dots carry no meaning to VoiceOver, so collapse them into one "Step 2 of 4" element.
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(Self.stepCount)")
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

            No telemetry, ever.
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
            // Seed a default only when the current pick isn't installed. onAppear fires again
            // when the user steps Back to here, and re-seeding would clobber their choice.
            guard !state.browsers.contains(where: { $0.bundleID == fallbackBundleID }) else { return }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.isDefaultBrowser)
            if state.isDefaultBrowser {
                Label("Junction is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Until you do, Junction never sees your links and rules won't run. You can set this later from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var starterRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starter rules").font(.title2.bold())
            Text("Pick any that fit — edit them later in Settings.")
                .foregroundStyle(.secondary)
            if availableTemplates.isEmpty {
                Text("No starter rules match the apps you have installed. You can add your own anytime in Settings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(availableTemplates) { template in
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
        if !isLastStep {
            step += 1
            return
        }
        state.updateConfig { config in
            config.fallback.app = fallbackBundleID
            let chosen = availableTemplates.filter { selectedTemplates.contains($0.id) }.map(\.rule)
            // Skip templates already present (re-running the tour must not duplicate rules).
            config.rules.append(contentsOf: chosen.filter { rule in !config.rules.contains(rule) })
        }
        onDone()
    }
}
#endif
