#if canImport(AppKit)
import AppKit
import Combine
import Foundation
import JunctionCore
import JunctionMacKit

/// One routed link, kept in memory only (never written to disk — PRD §12).
struct RecentLink: Identifiable {
    let id = UUID()
    let date: Date
    let url: URL
    let sourceApp: String?
    let outcome: String
}

@MainActor
final class AppState: ObservableObject {
    let configStore: ConfigStore
    @Published private(set) var engine: RoutingEngine
    @Published private(set) var recentLinks: [RecentLink] = []
    @Published private(set) var configError: ConfigError?
    @Published var routingPaused = false
    @Published private(set) var browsers: [Browser] = []
    @Published private(set) var isDefaultBrowser = false

    /// Injected by AppDelegate so state doesn't own window controllers.
    var pickerPresenter: ((URL) -> Void)?
    var settingsPresenter: (() -> Void)?
    var onboardingPresenter: (() -> Void)?

    /// Built-ins merged with the user's `customRewriters` — the engine owns the merge.
    var rewriters: RewriterStore { engine.rewriters }
    private let maxRecent = 10

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        self.engine = RoutingEngine(
            config: configStore.config,
            isSchemeHandled: { BrowserDiscovery.isSchemeHandled($0) }
        )
        configStore.onChange = { [weak self] config in
            self?.rebuildEngine(with: config)
            self?.configError = nil
        }
        configStore.onError = { [weak self] error in
            self?.configError = error
        }
        self.configError = configStore.lastError
        refreshBrowsers()
        refreshDefaultBrowserStatus()
    }

    private func rebuildEngine(with config: Config) {
        engine = RoutingEngine(
            config: config,
            isSchemeHandled: { BrowserDiscovery.isSchemeHandled($0) }
        )
    }

    var config: Config { configStore.config }

    func updateConfig(_ mutate: (inout Config) -> Void) {
        var c = configStore.config
        mutate(&c)
        do {
            try configStore.save(c)
        } catch let e as ConfigError {
            configError = e
        } catch {
            configError = .unreadable(String(describing: error))
        }
    }

    // MARK: Routing

    func handle(_ event: LinkEvent) {
        if routingPaused {
            openInFallback(event.url)
            record(event, outcome: "paused → fallback")
            return
        }
        let trace = engine.trace(event)
        let dispatcher = Dispatcher(fallbackApp: config.fallback.app)
        let outcome = dispatcher.dispatch(trace.decision)

        switch outcome {
        case .needsPicker(let url):
            pickerPresenter?(url)
            record(event, outcome: "picker")
            // A rule whose target vanished degrades to the picker fallback; still tell
            // the user the rule is broken (one-time), like the browser-fallback path.
            switch trace.decision {
            case .open(let app, _, _):
                notifyBrokenRule(reason: "\(app) is not installed", rule: trace.matchedRule)
            case .deepLink(let deepURL, _, _):
                notifyBrokenRule(reason: "No app installed for \(deepURL.scheme ?? "?")://", rule: trace.matchedRule)
            default:
                break
            }
        case .degradedToFallback(let reason):
            record(event, outcome: "fallback (\(reason))")
            notifyBrokenRule(reason: reason, rule: trace.matchedRule)
        case .copiedToClipboard:
            record(event, outcome: "copied")
            showCopiedConfirmation()
        case .failed(let message):
            openInFallback(event.url)
            record(event, outcome: "failed (\(message)) → fallback")
        case .opened:
            record(event, outcome: describe(trace))
        }
    }

    func openInFallback(_ url: URL) {
        let outcome = Dispatcher(fallbackApp: config.fallback.app)
            .dispatch(.fallback(app: config.fallback.app, url: url))
        // Picker-as-fallback: the dispatcher can't show UI, so it hands back here.
        if case .needsPicker(let url) = outcome { pickerPresenter?(url) }
    }

    func open(url: URL, in browser: Browser, profile: BrowserProfile?) {
        let outcome = Dispatcher(fallbackApp: config.fallback.app)
            .openInBrowser(bundleID: browser.bundleID, profile: profile?.directory, url: url)
        // The picked browser vanished mid-pick and the fallback is the picker: re-ask.
        if case .needsPicker(let url) = outcome { pickerPresenter?(url) }
    }

    private func describe(_ trace: RoutingTrace) -> String {
        switch trace.decision {
        case .open(let app, let profile, _):
            let name = browsers.first(where: { $0.bundleID == app })?.name ?? app
            return profile.map { "\(name) (\($0))" } ?? name
        case .deepLink(_, let id, _):
            return rewriters.rewriter(id: id)?.name ?? id
        case .prompt: return "picker"
        case .clipboard: return "copied"
        case .fallback: return "fallback"
        }
    }

    private func record(_ event: LinkEvent, outcome: String) {
        recentLinks.insert(
            RecentLink(date: Date(), url: event.url, sourceApp: event.sourceApp, outcome: outcome),
            at: 0
        )
        if recentLinks.count > maxRecent {
            recentLinks.removeLast(recentLinks.count - maxRecent)
        }
    }

    /// Transient "Link copied" HUD near the cursor — a clipboard action otherwise
    /// looks like nothing happened.
    func showCopiedConfirmation() {
        let label = NSTextField(labelWithString: "Link copied")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.sizeToFit()

        let effect = NSVisualEffectView(frame: label.bounds.insetBy(dx: -16, dy: -10))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        label.setFrameOrigin(NSPoint(x: 16, y: 10))
        effect.addSubview(label)

        let panel = NSPanel(
            contentRect: effect.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y + 12))
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            panel.close()
        }
    }

    private var notifiedReasons = Set<String>()
    /// One-time notification when a rule's target is missing (PRD §11).
    private func notifyBrokenRule(reason: String, rule: String?) {
        guard !notifiedReasons.contains(reason) else { return }
        notifiedReasons.insert(reason)
        let alert = NSAlert()
        alert.messageText = "Junction used your fallback browser"
        alert.informativeText = rule.map { "Rule \"\($0)\": \(reason)" } ?? reason
        alert.addButton(withTitle: "Fix Rule…")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            settingsPresenter?()
        }
    }

    // MARK: Environment

    func refreshBrowsers() {
        browsers = BrowserDiscovery.installedBrowsers()
    }

    func refreshDefaultBrowserStatus() {
        let https = URL(string: "https://example.com")!
        let current = NSWorkspace.shared.urlForApplication(toOpen: https)
        let mine = Bundle.main.bundleURL
        isDefaultBrowser = current?.standardizedFileURL == mine.standardizedFileURL
    }

    func requestDefaultBrowser() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "http"
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.refreshDefaultBrowserStatus()
            }
        }
    }
}
#endif
