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

/// Executes routing decisions via NSWorkspace. Shared by the app and `junction open`.
public struct Dispatcher {
    public var fallbackApp: String

    public init(fallbackApp: String) {
        self.fallbackApp = fallbackApp
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
            _ = openInBrowser(bundleID: fallbackApp, profile: nil, url: originalURL, completion: completion)
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
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // Target browser missing (e.g. dotfiles synced to a Mac without it) → fallback.
            if bundleID != fallbackApp,
               let fallbackURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallbackApp) {
                open(url: url, appURL: fallbackURL, bundleID: fallbackApp, profile: nil, completion: completion)
                return .degradedToFallback(reason: "\(bundleID) is not installed")
            }
            // Last resort: system default handler.
            NSWorkspace.shared.open(url)
            completion?(.degradedToFallback(reason: "\(bundleID) is not installed"))
            return .degradedToFallback(reason: "\(bundleID) is not installed")
        }

        // A renamed or deleted Firefox profile can't be caught by Firefox: `-P unknown` doesn't
        // error, it hands the URL to whatever instance happens to be running. Catch it here so
        // the link lands somewhere predictable instead of a silently wrong profile.
        if let profile,
           BrowserDiscovery.family(forBundleID: bundleID) == .firefox,
           !FirefoxProfiles.profiles(for: bundleID).contains(where: { $0.directory == profile }) {
            let reason = "Firefox profile \"\(profile)\" no longer exists"
            if bundleID != fallbackApp,
               let fallbackURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallbackApp) {
                open(url: url, appURL: fallbackURL, bundleID: fallbackApp, profile: nil, completion: completion)
            } else {
                open(url: url, appURL: appURL, bundleID: bundleID, profile: nil, completion: completion)
            }
            return .degradedToFallback(reason: reason)
        }

        open(url: url, appURL: appURL, bundleID: bundleID, profile: profile, completion: completion)
        return .opened
    }

    /// The launch flag that selects a profile, per browser family.
    /// Chromium: `--profile-directory=<dir>`. Firefox: `-P <name>` (verified on Firefox 152 —
    /// it starts a second instance when another profile is live, and forwards when that same
    /// profile is already running, so no `-no-remote` is needed).
    private func profileArguments(bundleID: String, profile: String, url: URL) -> [String]? {
        switch BrowserDiscovery.family(forBundleID: bundleID) {
        case .chromium: return ["--profile-directory=\(profile)", url.absoluteString]
        case .firefox: return ["-P", profile, url.absoluteString]
        case .other: return nil
        }
    }

    private func open(
        url: URL,
        appURL: URL,
        bundleID: String,
        profile: String?,
        completion: (@Sendable (DispatchOutcome) -> Void)?
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let profile, let arguments = profileArguments(bundleID: bundleID, profile: profile, url: url) {
            // arguments are only honored for a *new* process, so force one. Both families'
            // singleton IPC hands the URL to the right running instance and the spawned
            // process exits. Works whether or not the browser is open.
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    completion?(.failed(error.localizedDescription))
                } else {
                    completion?(.opened)
                }
            }
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    completion?(.failed(error.localizedDescription))
                } else {
                    completion?(.opened)
                }
            }
        }
    }
}
#endif
