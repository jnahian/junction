#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore

public enum DispatchOutcome: Sendable {
    case opened
    /// Target missing → routed to fallback instead. Carries a user-facing explanation.
    case degradedToFallback(reason: String)
    case copiedToClipboard
    /// The caller (app) must show the picker for this URL.
    case needsPicker(URL)
    case failed(String)
}

/// Result for one native browser request containing an ordered batch of links.
public enum BrowserBatchOutcome: Sendable {
    case opened
    case needsPicker
    case failed(String)
    case degradedToFallback(reason: String)

    fileprivate func singleURL(_ url: URL) -> DispatchOutcome {
        switch self {
        case .opened: return .opened
        case .needsPicker: return .needsPicker(url)
        case .failed(let message): return .failed(message)
        case .degradedToFallback(let reason): return .degradedToFallback(reason: reason)
        }
    }
}

/// Executes routing decisions via NSWorkspace. Shared by the app and `junction open`.
public struct Dispatcher {
    public var fallbackApp: String
    private let environment: Environment

    /// Resolve once and launch once per batch. Tests replace only these OS boundaries.
    struct Environment {
        var applicationURL: (String) -> URL?
        var family: (String) -> BrowserFamily
        var firefoxProfileExists: (String, String) -> Bool
        var openURLs: ([URL], URL, NSWorkspace.OpenConfiguration, (@Sendable (BrowserBatchOutcome) -> Void)?) -> Void
        var openApplication: (URL, NSWorkspace.OpenConfiguration, (@Sendable (BrowserBatchOutcome) -> Void)?) -> Void
        var openDefault: (URL) -> Void

        static var live: Self {
            Self(
                applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
                family: { BrowserDiscovery.family(forBundleID: $0) },
                firefoxProfileExists: { bundleID, profile in
                    FirefoxProfiles.profiles(for: bundleID).contains { $0.directory == profile }
                },
                openURLs: { urls, appURL, configuration, completion in
                    NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
                        completion?(error.map { .failed($0.localizedDescription) } ?? .opened)
                    }
                },
                openApplication: { appURL, configuration, completion in
                    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                        completion?(error.map { .failed($0.localizedDescription) } ?? .opened)
                    }
                },
                openDefault: { NSWorkspace.shared.open($0) }
            )
        }
    }

    public init(fallbackApp: String) {
        self.fallbackApp = fallbackApp
        self.environment = .live
    }

    init(fallbackApp: String, environment: Environment) {
        self.fallbackApp = fallbackApp
        self.environment = environment
    }

    @discardableResult
    public func dispatch(_ decision: RoutingDecision, completion: (@Sendable (DispatchOutcome) -> Void)? = nil) -> DispatchOutcome {
        switch decision {
        case .open(let app, let profile, let url):
            return openInBrowser(bundleID: app, profile: profile, url: url, completion: completion)

        case .deepLink(let url, _, let originalURL):
            // Scheme handler presence was checked at routing time, but the app may have
            // been removed since; degrade to fallback rather than losing the link.
            if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                NSWorkspace.shared.open(url)
                completion?(.opened)
                return .opened
            }
            let outcome = openInBrowser(bundleID: fallbackApp, profile: nil, url: originalURL, completion: completion)
            if case .needsPicker = outcome { return outcome }
            return .degradedToFallback(reason: "No app installed for \(url.scheme ?? "?")://")

        case .prompt(let url):
            completion?(.needsPicker(url))
            return .needsPicker(url)

        case .clipboard(let url):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            completion?(.copiedToClipboard)
            return .copiedToClipboard

        case .fallback(let app, let url):
            return openInBrowser(bundleID: app, profile: nil, url: url, completion: completion)
        }
    }

    @discardableResult
    public func openInBrowser(
        bundleID: String,
        profile: String?,
        url: URL,
        completion: (@Sendable (DispatchOutcome) -> Void)? = nil
    ) -> DispatchOutcome {
        let batchCompletion: (@Sendable (BrowserBatchOutcome) -> Void)?
        if let completion {
            batchCompletion = { outcome in completion(outcome.singleURL(url)) }
        } else {
            batchCompletion = nil
        }
        return openInBrowser(bundleID: bundleID, profile: profile, urls: [url], completion: batchCompletion)
            .singleURL(url)
    }

    /// Immediate results retain the single-link API's behavior. For a native launch,
    /// completion reports the eventual result and may run on a concurrent queue.
    @discardableResult
    public func openInBrowser(
        bundleID: String,
        profile: String?,
        urls: [URL],
        completion: (@Sendable (BrowserBatchOutcome) -> Void)? = nil
    ) -> BrowserBatchOutcome {
        guard !urls.isEmpty else {
            completion?(.opened)
            return .opened
        }
        guard let appURL = environment.applicationURL(bundleID) else {
            // Never hand the picker sentinel to the system default (possibly Junction).
            if fallbackApp == Fallback.picker {
                completion?(.needsPicker)
                return .needsPicker
            }
            if bundleID != fallbackApp, let fallbackURL = environment.applicationURL(fallbackApp) {
                open(urls: urls, appURL: fallbackURL, bundleID: fallbackApp, profile: nil, completion: completion)
                return .degradedToFallback(reason: "\(bundleID) is not installed")
            }
            // Preserve the legacy last resort when neither named browser exists.
            for url in urls { environment.openDefault(url) }
            let outcome = BrowserBatchOutcome.degradedToFallback(reason: "\(bundleID) is not installed")
            completion?(outcome)
            return outcome
        }

        // Resolve a deleted Firefox profile once, so the entire batch goes to one destination.
        if let profile,
           environment.family(bundleID) == .firefox,
           !environment.firefoxProfileExists(bundleID, profile) {
            let reason = "Firefox profile \"\(profile)\" no longer exists"
            if bundleID != fallbackApp, let fallbackURL = environment.applicationURL(fallbackApp) {
                open(urls: urls, appURL: fallbackURL, bundleID: fallbackApp, profile: nil, completion: completion)
            } else {
                open(urls: urls, appURL: appURL, bundleID: bundleID, profile: nil, completion: completion)
            }
            return .degradedToFallback(reason: reason)
        }

        open(urls: urls, appURL: appURL, bundleID: bundleID, profile: profile, completion: completion)
        return .opened
    }

    private func open(
        urls: [URL],
        appURL: URL,
        bundleID: String,
        profile: String?,
        completion: (@Sendable (BrowserBatchOutcome) -> Void)?
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        var profileArguments: [String]?
        if let profile {
            switch environment.family(bundleID) {
            case .chromium: profileArguments = ["--profile-directory=\(profile)"]
            case .firefox: profileArguments = ["-P", profile]
            case .other: break
            }
        }
        if let profileArguments {
            // Profile switches require a new process. Launch once with all URLs, rather
            // than racing multiple processes through the browser's singleton forwarding.
            configuration.arguments = profileArguments + urls.map(\.absoluteString)
            configuration.createsNewApplicationInstance = true
            environment.openApplication(appURL, configuration, completion)
        } else {
            environment.openURLs(urls, appURL, configuration, completion)
        }
    }
}
#endif
