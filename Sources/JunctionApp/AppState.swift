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

/// What turning on iCloud sync needs the user to decide.
struct ICloudSyncChoice {
    let message: String
    let keepThisMacLabel: String
    let canUseICloud: Bool
}

@MainActor
final class AppState: ObservableObject {
    let configStore: ConfigStore
    let configMirror: ConfigMirror
    @Published private(set) var iCloudSyncOn: Bool
    @Published private(set) var iCloudSyncProblem: String?
    @Published var iCloudSyncChoice: ICloudSyncChoice?
    @Published private(set) var engine: RoutingEngine
    @Published private(set) var recentLinks: [RecentLink] = []
    @Published private(set) var configError: ConfigError?
    @Published var routingPaused = false
    @Published private(set) var browsers: [Browser] = []
    /// Rule targets only: a web app can't open links from other sites, so the picker and
    /// fallback stay browser-only.
    @Published private(set) var webApps: [ChromiumWebApp] = []
    /// macOS refused to let Junction read a browser's profile list (needs Full Disk Access).
    @Published private(set) var profileAccessBlocked = false
    @Published private(set) var isDefaultBrowser = false

    /// Injected by AppDelegate so state doesn't own window controllers.
    var pickerPresenter: ((URL) -> Void)?
    var settingsPresenter: (() -> Void)?
    var onboardingPresenter: (() -> Void)?

    /// Built-ins merged with the user's `customRewriters` — the engine owns the merge.
    var rewriters: RewriterStore { engine.rewriters }
    private let maxRecent = 10

    init(configStore: ConfigStore = ConfigStore(), configMirror: ConfigMirror? = nil) {
        self.configStore = configStore
        self.configMirror = configMirror ?? ConfigMirror(localURL: configStore.fileURL)
        self.iCloudSyncOn = self.configMirror.isEnabled
        self.engine = RoutingEngine(
            config: configStore.config,
            isSchemeHandled: { BrowserDiscovery.isSchemeHandled($0) }
        )
        configStore.onChange = { [weak self] config in
            self?.rebuildEngine(with: config)
            self?.configError = nil
            self?.configMirror.reconcile()
        }
        configStore.onError = { [weak self] error in
            self?.configError = error
        }
        self.configMirror.onProblem = { [weak self] problem in
            self?.iCloudSyncProblem = problem
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

    // MARK: iCloud sync

    func turnOnICloudSync() {
        iCloudSyncProblem = nil
        configMirror.checkRemote { [weak self] remote in
            guard let self else { return }
            switch remote {
            case .matches:
                self.finishTurningOnICloudSync(keeping: .thisMac)
            case .missing:
                self.iCloudSyncChoice = ICloudSyncChoice(
                    message: "iCloud Drive has no Junction rules yet. If another Mac already syncs, wait for iCloud to catch up and try again, or this Mac's rules will replace them.",
                    keepThisMacLabel: "Upload This Mac's Rules",
                    canUseICloud: false
                )
            case .differs:
                self.iCloudSyncChoice = ICloudSyncChoice(
                    message: "iCloud Drive already has different rules. The set you don't keep is saved as config.backup.json next to your config file.",
                    keepThisMacLabel: "Replace with This Mac's Rules",
                    canUseICloud: true
                )
            case .invalid(let problem):
                self.iCloudSyncChoice = ICloudSyncChoice(
                    message: "The copy in iCloud Drive can't be used. \(problem)",
                    keepThisMacLabel: "Replace with This Mac's Rules",
                    canUseICloud: false
                )
            case .unreadable(let problem):
                self.iCloudSyncProblem = problem
            }
        }
    }

    func finishTurningOnICloudSync(keeping source: ConfigMirror.Source) {
        if source == .thisMac { nameRuleProfiles() }
        configMirror.enable(from: source) { [weak self] failure in
            guard let self else { return }
            self.iCloudSyncProblem = failure
            self.iCloudSyncOn = failure == nil
            if failure == nil { self.configMirror.startWatching() }
        }
    }

    func turnOffICloudSync() {
        configMirror.disable()
        iCloudSyncOn = false
        iCloudSyncProblem = nil
    }

    /// Directories mean different profiles on different Macs, so what other Macs receive has
    /// to use names. Only the Mac that wrote a directory can tell which profile it meant.
    private func nameRuleProfiles() {
        var named = config
        for index in named.rules.indices {
            guard case .open(let app, let profile?) = named.rules[index].action else { continue }
            let browser = webApps.first { $0.bundleID == app }?.browserBundleID ?? app
            let profiles = ChromiumProfiles.profiles(for: browser)
            if let match = profiles.first(where: { $0.directory == profile }) {
                named.rules[index].action = .open(app: app, profile: profiles.ruleValue(for: match))
            }
        }
        if named != config { updateConfig { $0 = named } }
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
                let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) != nil
                notifyBrokenRule(
                    reason: installed ? "\(app) couldn't open this link" : "\(app) is not installed",
                    rule: trace.matchedRule
                )
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
        openInFallback(urls: [url])
    }

    /// One native request for the whole batch — issuing them per link races a cold-starting
    /// browser the same way the picker used to.
    func openInFallback(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let outcome = Dispatcher(fallbackApp: config.fallback.app)
            .openInBrowser(bundleID: config.fallback.app, profile: nil, urls: urls)
        // Picker-as-fallback: the dispatcher can't show UI, so it hands back here.
        if case .needsPicker = outcome {
            for url in urls { pickerPresenter?(url) }
        }
    }

    func open(
        urls: [URL],
        in browser: Browser,
        profile: BrowserProfile?,
        completion: @escaping @MainActor (BrowserBatchOutcome) -> Void
    ) {
        Dispatcher(fallbackApp: config.fallback.app)
            .openInBrowser(bundleID: browser.bundleID, profile: profile?.directory, urls: urls) { outcome in
                // NSWorkspace completes on a concurrent queue. The picker owns retries
                // and finalizes the whole batch on the main actor.
                Task { @MainActor in completion(outcome) }
            }
    }

    private func describe(_ trace: RoutingTrace) -> String {
        switch trace.decision {
        case .open(let app, let profile, _):
            let name = browsers.first(where: { $0.bundleID == app })?.name
                ?? webApps.first(where: { $0.bundleID == app })?.name ?? app
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
    func showCopiedConfirmation(count: Int = 1) {
        let label = NSTextField(labelWithString: count == 1 ? "Link copied" : "\(count) links copied")
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
        webApps = BrowserDiscovery.installedWebApps()
        profileAccessBlocked = BrowserDiscovery.isProfileAccessBlocked(browsers)
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
