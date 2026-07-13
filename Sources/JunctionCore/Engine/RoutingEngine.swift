import Foundation

/// A rule with its matchers pre-compiled. Built once per config load — never on the click path.
struct CompiledRule: @unchecked Sendable {
    let index: Int
    let rule: Rule
    let patterns: [WildcardPattern]
    let regex: NSRegularExpression?
    let sourceApps: Set<String>
    let rewrite: (find: NSRegularExpression, replace: String)?

    init?(index: Int, rule: Rule) {
        guard rule.enabled, !rule.match.isEmpty else { return nil }
        self.index = index
        self.rule = rule
        // If any pattern is invalid the whole rule is skipped (never silently
        // widened to match-all). ConfigStore.validate reports this to the user.
        let compiled = rule.match.patterns.map { WildcardPattern($0) }
        guard !compiled.contains(where: { $0 == nil }) else { return nil }
        self.patterns = compiled.compactMap { $0 }
        if let r = rule.match.regex {
            guard let compiledRegex = try? NSRegularExpression(pattern: r, options: []) else { return nil }
            self.regex = compiledRegex
        } else {
            self.regex = nil
        }
        self.sourceApps = Set(rule.match.sourceApps.map { $0.lowercased() })
        if let rw = rule.rewrite, let find = try? NSRegularExpression(pattern: rw.find, options: []) {
            self.rewrite = (find, rw.replace)
        } else {
            self.rewrite = nil
        }
    }

    func matches(_ event: LinkEvent) -> Bool {
        // AND across matcher kinds; OR within each list.
        if !patterns.isEmpty || regex != nil {
            var urlMatched = false
            if patterns.contains(where: { $0.matches(event.url) }) { urlMatched = true }
            if !urlMatched, let regex {
                let s = event.url.absoluteString
                if regex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)) != nil {
                    urlMatched = true
                }
            }
            guard urlMatched else { return false }
        }
        if !sourceApps.isEmpty {
            guard let src = event.sourceApp?.lowercased(), sourceApps.contains(src) else { return false }
        }
        return true
    }
}

/// Pure, UI-free routing engine. First matching rule wins; enabled built-in rewriters
/// run when no rule matched; otherwise the fallback browser.
public struct RoutingEngine: Sendable {
    public let config: Config
    public let rewriters: RewriterStore
    private let compiled: [CompiledRule]
    private let stripper: TrackingParamStripper
    /// Injected so the core stays platform-free. Return whether an app that handles
    /// the given URL scheme is installed. Defaults to "assume installed".
    public var isSchemeHandled: @Sendable (String) -> Bool

    /// `rewriters` is the *base* pack, not the final one: `config.customRewriters` is always
    /// merged in on top, so passing an empty store does not mean "no rewriters".
    public init(
        config: Config,
        rewriters: RewriterStore = .builtin(),
        isSchemeHandled: @escaping @Sendable (String) -> Bool = { _ in true }
    ) {
        self.config = config
        self.rewriters = rewriters.merging(custom: config.customRewriters)
        self.compiled = config.rules.enumerated().compactMap { CompiledRule(index: $0.offset, rule: $0.element) }
        self.stripper = TrackingParamStripper.builtin(extra: config.extraTrackingParams)
        self.isSchemeHandled = isSchemeHandled
    }

    public func route(_ event: LinkEvent) -> RoutingDecision {
        trace(event).decision
    }

    /// Full evaluation with trace — used by the tester UI and CLI.
    public func trace(_ event: LinkEvent) -> RoutingTrace {
        var url = event.url

        // Global transform: strip tracking params.
        if config.stripTrackingParams {
            url = stripper.strip(url)
        }
        let transformedURL = url
        var event = event
        event.url = url

        // ⌥-click escape hatch beats everything.
        if event.forcePicker {
            return RoutingTrace(
                input: event, transformedURL: transformedURL,
                matchedRule: nil, matchedRuleIndex: nil, rewriterID: nil,
                decision: .prompt(url: url)
            )
        }

        // Ordered rules, first match wins.
        for c in compiled where c.matches(event) {
            var url = url
            if let rw = c.rewrite { // pre-compiled on config load, never on the click path
                let s = url.absoluteString
                let out = rw.find.stringByReplacingMatches(
                    in: s, options: [],
                    range: NSRange(s.startIndex..<s.endIndex, in: s),
                    withTemplate: rw.replace
                )
                if let rewritten = URL(string: out) { url = rewritten }
            }

            let decision = decide(action: c.rule.action, url: url)
            var firedRewriter: String?
            if case .deepLink(_, let id, _) = decision { firedRewriter = id }
            return RoutingTrace(
                input: event, transformedURL: transformedURL,
                matchedRule: c.rule.name, matchedRuleIndex: c.index,
                rewriterID: firedRewriter,
                decision: decision
            )
        }

        // Built-in rewriters (opt-in + target installed) before fallback.
        for rewriter in rewriters.rewriters where config.enabledRewriters.contains(rewriter.id) {
            guard isSchemeHandled(rewriter.scheme),
                  let rewritten = rewriter.rewrite(url, lookup: config.slackTeams) else { continue }
            return RoutingTrace(
                input: event, transformedURL: transformedURL,
                matchedRule: nil, matchedRuleIndex: nil, rewriterID: rewriter.id,
                decision: .deepLink(url: rewritten, rewriterID: rewriter.id, originalURL: url)
            )
        }

        return RoutingTrace(
            input: event, transformedURL: transformedURL,
            matchedRule: nil, matchedRuleIndex: nil, rewriterID: nil,
            decision: .fallback(app: config.fallback.app, url: url)
        )
    }

    private func decide(action: Action, url: URL) -> RoutingDecision {
        switch action {
        case .open(let app, let profile):
            return .open(app: app, profile: profile, url: url)
        case .deepLink(let id):
            guard let rewriter = rewriters.rewriter(id: id),
                  isSchemeHandled(rewriter.scheme),
                  let rewritten = rewriter.rewrite(url, lookup: config.slackTeams) else {
                // Rewriter unknown, app missing, URL didn't match, or (Slack) the workspace has
                // no team ID mapped → never lose a link.
                return .fallback(app: config.fallback.app, url: url)
            }
            return .deepLink(url: rewritten, rewriterID: id, originalURL: url)
        case .prompt:
            return .prompt(url: url)
        case .clipboard:
            return .clipboard(url: url)
        }
    }
}
