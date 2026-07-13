import Foundation

/// Root of `~/.config/junction/config.json`.
public struct Config: Codable, Equatable, Sendable {
    public var version: Int
    public var fallback: Fallback
    public var stripTrackingParams: Bool
    /// Extra tracking params to strip, on top of the built-in list.
    public var extraTrackingParams: [String]
    /// Rewriter IDs the user has switched on. All built-ins are OFF by default —
    /// automatic deep-linking is opt-in. (Explicit `deepLink` rule actions always work.)
    public var enabledRewriters: [String]
    /// User-defined deep-link apps, same shape as the built-in `rewriters.json` entries.
    /// They shadow a built-in sharing the same id, and — like built-ins — only fire
    /// automatically once listed in `enabledRewriters`.
    public var customRewriters: [Rewriter]
    /// Slack workspace subdomain → team ID (`{"acme": "T01ABCDEF"}`). Slack's deep-link
    /// scheme takes team IDs only, and a permalink carries just the subdomain, so without
    /// this map a Slack link can't be deep-linked and falls back to the browser.
    public var slackTeams: [String: String]
    public var rules: [Rule]

    public init(
        version: Int = 1,
        fallback: Fallback = Fallback(app: "com.apple.Safari"),
        stripTrackingParams: Bool = true,
        extraTrackingParams: [String] = [],
        enabledRewriters: [String] = [],
        customRewriters: [Rewriter] = [],
        slackTeams: [String: String] = [:],
        rules: [Rule] = []
    ) {
        self.version = version
        self.fallback = fallback
        self.stripTrackingParams = stripTrackingParams
        self.extraTrackingParams = extraTrackingParams
        self.enabledRewriters = enabledRewriters
        self.customRewriters = customRewriters
        self.slackTeams = slackTeams
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case version, fallback, stripTrackingParams, extraTrackingParams, enabledRewriters,
             customRewriters, slackTeams, rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? Fallback(app: "com.apple.Safari")
        stripTrackingParams = try c.decodeIfPresent(Bool.self, forKey: .stripTrackingParams) ?? true
        extraTrackingParams = try c.decodeIfPresent([String].self, forKey: .extraTrackingParams) ?? []
        enabledRewriters = try c.decodeIfPresent([String].self, forKey: .enabledRewriters) ?? []
        customRewriters = try c.decodeIfPresent([Rewriter].self, forKey: .customRewriters) ?? []
        slackTeams = try c.decodeIfPresent([String: String].self, forKey: .slackTeams) ?? [:]
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

public struct Fallback: Codable, Equatable, Sendable {
    /// Bundle identifier of the catch-all browser.
    public var app: String
    public init(app: String) { self.app = app }
}

public struct Rule: Codable, Sendable, Identifiable {
    /// Stable identity for GUI list handling. Not persisted; derived from position+name if absent.
    public var id: UUID
    public var name: String
    public var notes: String?
    public var enabled: Bool
    public var match: Match
    public var action: Action
    /// Optional per-rule URL rewrite applied before the action.
    public var rewrite: RegexRewrite?

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        enabled: Bool = true,
        match: Match,
        action: Action,
        rewrite: RegexRewrite? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.enabled = enabled
        self.match = match
        self.action = action
        self.rewrite = rewrite
    }

    enum CodingKeys: String, CodingKey {
        case name, notes, enabled, match, action, rewrite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled rule"
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        match = try c.decode(Match.self, forKey: .match)
        action = try c.decode(Action.self, forKey: .action)
        rewrite = try c.decodeIfPresent(RegexRewrite.self, forKey: .rewrite)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(notes, forKey: .notes)
        if !enabled { try c.encode(enabled, forKey: .enabled) }
        try c.encode(match, forKey: .match)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(rewrite, forKey: .rewrite)
    }
}

extension Rule: Equatable {
    /// Equality ignores the ephemeral GUI `id` — it isn't persisted.
    public static func == (lhs: Rule, rhs: Rule) -> Bool {
        lhs.name == rhs.name
            && lhs.notes == rhs.notes
            && lhs.enabled == rhs.enabled
            && lhs.match == rhs.match
            && lhs.action == rhs.action
            && lhs.rewrite == rhs.rewrite
    }
}

/// Matchers within a rule are AND-ed; entries inside `patterns`/`sourceApps` are OR-ed.
public struct Match: Codable, Equatable, Sendable {
    /// Wildcard patterns matched against host+path (see WildcardPattern).
    public var patterns: [String]
    /// Opt-in regex over the full URL string.
    public var regex: String?
    /// Bundle IDs of apps the click originated from.
    public var sourceApps: [String]

    public init(patterns: [String] = [], regex: String? = nil, sourceApps: [String] = []) {
        self.patterns = patterns
        self.regex = regex
        self.sourceApps = sourceApps
    }

    enum CodingKeys: String, CodingKey { case patterns, regex, sourceApps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patterns = try c.decodeIfPresent([String].self, forKey: .patterns) ?? []
        regex = try c.decodeIfPresent(String.self, forKey: .regex)
        sourceApps = try c.decodeIfPresent([String].self, forKey: .sourceApps) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !patterns.isEmpty { try c.encode(patterns, forKey: .patterns) }
        try c.encodeIfPresent(regex, forKey: .regex)
        if !sourceApps.isEmpty { try c.encode(sourceApps, forKey: .sourceApps) }
    }

    public var isEmpty: Bool { patterns.isEmpty && regex == nil && sourceApps.isEmpty }
}

/// What to do with a matched URL. Encoded as a one-of JSON object:
/// `{"app": "...", "profile": "..."}` | `{"deepLink": "zoom"}` | `{"prompt": true}` | `{"clipboard": true}`
public enum Action: Equatable, Sendable {
    case open(app: String, profile: String?)
    case deepLink(String)
    case prompt
    case clipboard

    enum CodingKeys: String, CodingKey { case app, profile, deepLink, prompt, clipboard }
}

extension Action: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let app = try c.decodeIfPresent(String.self, forKey: .app) {
            self = .open(app: app, profile: try c.decodeIfPresent(String.self, forKey: .profile))
        } else if let id = try c.decodeIfPresent(String.self, forKey: .deepLink) {
            self = .deepLink(id)
        } else if try c.decodeIfPresent(Bool.self, forKey: .prompt) == true {
            self = .prompt
        } else if try c.decodeIfPresent(Bool.self, forKey: .clipboard) == true {
            self = .clipboard
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Action must contain one of: app, deepLink, prompt, clipboard"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .open(let app, let profile):
            try c.encode(app, forKey: .app)
            try c.encodeIfPresent(profile, forKey: .profile)
        case .deepLink(let id):
            try c.encode(id, forKey: .deepLink)
        case .prompt:
            try c.encode(true, forKey: .prompt)
        case .clipboard:
            try c.encode(true, forKey: .clipboard)
        }
    }
}

/// Find/replace regex rewrite applied to the URL string before the action runs.
public struct RegexRewrite: Codable, Equatable, Sendable {
    public var find: String
    public var replace: String
    public init(find: String, replace: String) {
        self.find = find
        self.replace = replace
    }
}
