import Foundation

/// An incoming link click, as seen by the routing engine.
public struct LinkEvent: Sendable, Equatable {
    public var url: URL
    /// Bundle ID of the app the click originated from, if it could be determined.
    public var sourceApp: String?
    /// True when the user held ⌥ Option — forces the picker.
    public var forcePicker: Bool

    public init(url: URL, sourceApp: String? = nil, forcePicker: Bool = false) {
        self.url = url
        self.sourceApp = sourceApp
        self.forcePicker = forcePicker
    }
}

/// The engine's verdict for a link event.
public enum RoutingDecision: Sendable, Equatable {
    /// Open in a browser (optionally a specific Chromium profile directory name).
    case open(app: String, profile: String?, url: URL)
    /// Open a rewritten native-app deep link. `originalURL` is kept for fallback if the scheme fails.
    case deepLink(url: URL, rewriterID: String, originalURL: URL)
    /// Show the floating picker.
    case prompt(url: URL)
    /// Copy to clipboard instead of opening.
    case clipboard(url: URL)
    /// No rule matched (or target missing) — open in the fallback browser.
    case fallback(app: String, url: URL)

    public var url: URL {
        switch self {
        case .open(_, _, let u), .prompt(let u), .clipboard(let u), .fallback(_, let u):
            return u
        case .deepLink(let u, _, _):
            return u
        }
    }
}

/// A trace of how a decision was reached — powers the rule tester (F8) and `junction test`.
public struct RoutingTrace: Sendable {
    public var input: LinkEvent
    /// URL after global transforms (tracking-param strip), before per-rule rewrite.
    public var transformedURL: URL
    /// Name of the matched rule, if any. `nil` means fallback or built-in rewriter.
    public var matchedRule: String?
    /// Index of the matched rule in the config's rule array.
    public var matchedRuleIndex: Int?
    /// Rewriter that fired (via rule action or automatic built-in).
    public var rewriterID: String?
    public var decision: RoutingDecision
}
