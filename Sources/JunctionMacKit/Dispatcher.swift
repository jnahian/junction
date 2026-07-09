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
                open(url: url, appURL: fallbackURL, profile: nil, completion: completion)
                return .degradedToFallback(reason: "\(bundleID) is not installed")
            }
            // Last resort: system default handler.
            NSWorkspace.shared.open(url)
            completion?(.degradedToFallback(reason: "\(bundleID) is not installed"))
            return .degradedToFallback(reason: "\(bundleID) is not installed")
        }
        open(url: url, appURL: appURL, profile: profile, completion: completion)
        return .opened
    }

    private func open(
        url: URL,
        appURL: URL,
        profile: String?,
        completion: (@Sendable (DispatchOutcome) -> Void)?
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let profile {
            // arguments are only honored for a *new* process, so force one; Chromium's
            // singleton IPC hands the URL+profile to the running instance and the
            // spawned process exits immediately. Works whether or not the browser is open.
            configuration.arguments = ["--profile-directory=\(profile)", url.absoluteString]
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
