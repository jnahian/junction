#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import ServiceManagement
import SwiftUI

/// First-launch flow (PRD §10): explain → pick fallback → set default → automate → send-off.
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
        guard let url = CoreResources.url(forResource: "starter-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(FileFormat.self, from: data) else { return [] }
        return parsed.templates
    }
}

private struct OnboardingView: View {
    @ObservedObject var state: AppState
    let onDone: () -> Void

    @State private var step = 0
    @State private var fallbackBundleID: String = Fallback.picker
    @State private var selectedTemplates: Set<String> = []
    /// Template id → browser the user picked for it (browser-opening templates only).
    @State private var templateBrowsers: [String: String] = [:]
    /// What this tour run has written, so Back-and-deselect can undo it without
    /// touching rewriters or rules the user configured outside the tour.
    @State private var appliedRewriters: Set<String> = []
    @State private var appliedRuleNames: Set<String> = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let templates = StarterTemplates.load()

    private static let rewriters = RewriterStore.builtin()
    private static let stepCount = 5
    private var isLastStep: Bool { step == Self.stepCount - 1 }
    /// Step 2 is the only one Junction can't work without, so name the opt-out instead of
    /// letting "Continue" quietly mean "no".
    private var isSkippingDefaultBrowser: Bool { step == 2 && !state.isDefaultBrowser }

    /// Deep-link templates only make sense when the target app is installed; browser
    /// templates let the user pick the browser, so any installed browser will do.
    private var availableTemplates: [StarterTemplate] {
        templates.filter { template in
            switch template.rule.action {
            case .open:
                return !state.browsers.isEmpty
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
                    case 3: starterRules
                    default: allSet
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
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Junction").font(.largeTitle.bold())
                    Text("Every link, in the right place")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, Metrics.controlSpacing)
            Text("""
            Junction becomes your default browser. When you click a link anywhere, \
            Junction checks your rules and instantly hands the link to the right \
            browser, browser profile, or native app — or asks you with a quick picker.

            No telemetry, ever.
            """)
        }
    }

    private var fallbackPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happens with unmatched links?").font(.title2.bold())
            Text("Any link that doesn't match a rule goes here. You can change this anytime.")
                .foregroundStyle(.secondary)
            Picker("Fallback", selection: $fallbackBundleID) {
                Text("Ask every time — Junction shows a quick picker")
                    .tag(Fallback.picker)
                ForEach(state.browsers) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .onAppear {
            state.refreshBrowsers()
            // Seed a default only when the current pick is neither the picker nor an
            // installed browser. onAppear fires again when the user steps Back to here,
            // and re-seeding would clobber their choice.
            guard fallbackBundleID != Fallback.picker,
                  !state.browsers.contains(where: { $0.bundleID == fallbackBundleID }) else { return }
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
            Divider()
            Toggle("Launch Junction at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Text("Keeps Junction in the menu bar and saves the first click from waiting for it to start.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var starterRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make your first links automatic").font(.title2.bold())
            Text("Until a rule or deep link takes over, Junction uses your fallback. Pick any that fit — everything can be changed later in Settings.")
                .foregroundStyle(.secondary)
            if availableTemplates.isEmpty {
                Text("None of the starter suggestions match the apps you have installed. You can add rules anytime in Settings.")
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
                // Browser templates aren't tied to the JSON's seed browser — pick your own.
                if selectedTemplates.contains(template.id),
                   case .open = template.rule.action {
                    Picker("Browser", selection: browserBinding(template)) {
                        ForEach(state.browsers) { b in Text(b.name).tag(b.bundleID) }
                    }
                    .frame(maxWidth: 260)
                    .padding(.leading, 20)
                }
            }
        }
        .onAppear { seedTemplateBrowsers() }
    }

    private func browserBinding(_ template: StarterTemplate) -> Binding<String> {
        Binding(
            get: { templateBrowsers[template.id] ?? "" },
            set: { templateBrowsers[template.id] = $0 }
        )
    }

    /// Default each browser template to its JSON seed when installed, else the chosen
    /// fallback browser, else the first browser found. Never re-seed a made choice.
    private func seedTemplateBrowsers() {
        for template in availableTemplates {
            guard case .open(let app, _) = template.rule.action, templateBrowsers[template.id] == nil else { continue }
            if state.browsers.contains(where: { $0.bundleID == app }) {
                templateBrowsers[template.id] = app
            } else if state.browsers.contains(where: { $0.bundleID == fallbackBundleID }) {
                templateBrowsers[template.id] = fallbackBundleID
            } else if let first = state.browsers.first {
                templateBrowsers[template.id] = first.bundleID
            }
        }
    }

    private var allSet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're all set").font(.title2.bold())
            HStack(spacing: 10) {
                if let icon = Self.menuBarIcon {
                    Image(nsImage: icon).accessibilityHidden(true)
                }
                Text("Junction lives in your menu bar — that's where rules, deep links, and recent activity are.")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Send a Test Link Through Junction") {
                state.handle(LinkEvent(
                    url: URL(string: "https://example.com/hello-from-junction")!,
                    sourceApp: Bundle.main.bundleIdentifier
                ))
            }
            Text("Watch it route: the picker asks, a rule or deep link opens instantly, anything else lands in your fallback browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let menuBarIcon: NSImage? = {
        guard let url = CoreResources.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private func advance() {
        // Step 3 is the last configuring step; apply there so the send-off's test link
        // routes through the choices just made. Re-applying after Back reconciles:
        // a deselected template's contribution is removed again, but only if this
        // tour run wrote it.
        if step == 3 { applyChoices() }
        if isLastStep { onDone() } else { step += 1 }
    }

    private func applyChoices() {
        state.updateConfig { config in
            config.fallback.app = fallbackBundleID
            for template in availableTemplates {
                let selected = selectedTemplates.contains(template.id)
                switch template.rule.action {
                case .deepLink(let id):
                    // Switching on the built-in rewriter beats copying its patterns into a
                    // rule: it stays maintained with rewriters.json and teaches Deep Links.
                    if selected {
                        if !config.enabledRewriters.contains(id) {
                            config.enabledRewriters.append(id)
                            appliedRewriters.insert(id)
                        }
                    } else if appliedRewriters.remove(id) != nil {
                        config.enabledRewriters.removeAll { $0 == id }
                    }
                case .open(let seedApp, let seedProfile):
                    if selected {
                        var rule = template.rule
                        let chosen = templateBrowsers[template.id] ?? seedApp
                        // The seed profile only means something on the seed browser.
                        rule.action = .open(app: chosen, profile: chosen == seedApp ? seedProfile : nil)
                        if !config.rules.contains(rule) {
                            // Replace an earlier run's variant of the same starter rule.
                            config.rules.removeAll { $0.name == rule.name }
                            config.rules.append(rule)
                            appliedRuleNames.insert(rule.name)
                        }
                    } else if appliedRuleNames.remove(template.rule.name) != nil {
                        config.rules.removeAll { $0.name == template.rule.name }
                    }
                case .prompt, .clipboard:
                    if selected {
                        if !config.rules.contains(template.rule) {
                            config.rules.append(template.rule)
                            appliedRuleNames.insert(template.rule.name)
                        }
                    } else if appliedRuleNames.remove(template.rule.name) != nil {
                        config.rules.removeAll { $0.name == template.rule.name }
                    }
                }
            }
        }
    }
}
#endif
