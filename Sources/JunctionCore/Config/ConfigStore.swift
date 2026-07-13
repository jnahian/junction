import Foundation

public enum ConfigError: Error, CustomStringConvertible {
    case unreadable(String)
    case parse(String)
    case invalid([String])

    public var description: String {
        switch self {
        case .unreadable(let m): return "Cannot read config: \(m)"
        case .parse(let m): return "Config is not valid JSON: \(m)"
        case .invalid(let problems): return "Config is invalid:\n  - " + problems.joined(separator: "\n  - ")
        }
    }
}

/// Loads, validates, persists, and watches `config.json`.
/// Reading tolerates JSONC (comments, trailing commas); writing emits strict,
/// pretty-printed JSON with sorted keys so git diffs stay clean.
public final class ConfigStore {
    public static let junctionBundleID = "com.jnahian.junction"

    public let fileURL: URL
    /// Last successfully loaded config. On invalid external edits this keeps the last-good value.
    public private(set) var config: Config
    /// Non-nil when the file on disk is currently invalid (warning badge state).
    public private(set) var lastError: ConfigError?
    /// Called on the main thread after every successful (re)load or error.
    public var onChange: ((Config) -> Void)?
    public var onError: ((ConfigError) -> Void)?

    private var watcher: FileWatcher?
    /// Set while we write, so our own saves don't trigger a reload cycle.
    private var suppressNextReload = false

    /// Default path: `$XDG_CONFIG_HOME/junction/config.json` or `~/.config/junction/config.json`.
    public static func defaultURL() -> URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("junction/config.json")
    }

    public init(fileURL: URL = ConfigStore.defaultURL()) {
        self.fileURL = fileURL
        self.config = Config()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                self.config = try Self.load(from: fileURL)
            } catch let e as ConfigError {
                self.lastError = e
            } catch {
                self.lastError = .unreadable(String(describing: error))
            }
        }
    }

    // MARK: Load / validate

    public static func load(from url: URL) throws -> Config {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
        let strict = JSONC.data(from: raw)
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: strict)
        } catch {
            throw ConfigError.parse(Self.describeDecodingError(error))
        }
        let problems = validate(config)
        guard problems.isEmpty else { throw ConfigError.invalid(problems) }
        return config
    }

    /// Returns human-readable problems; empty means valid.
    public static func validate(_ config: Config) -> [String] {
        var problems: [String] = []
        if config.fallback.app.isEmpty {
            problems.append("fallback.app must be a bundle identifier")
        }
        if config.fallback.app.lowercased() == junctionBundleID {
            problems.append("fallback cannot target Junction itself (loop)")
        }
        var seenRewriterIDs = Set<String>()
        for (i, r) in config.customRewriters.enumerated() {
            let label = "custom rewriter \(i + 1) (\(r.name))"
            if r.id.isEmpty { problems.append("\(label): needs an id") }
            if !seenRewriterIDs.insert(r.id).inserted {
                problems.append("\(label): duplicate id \"\(r.id)\"")
            }
            if r.scheme.isEmpty { problems.append("\(label): needs the target app's URL scheme") }
            if r.template.isEmpty { problems.append("\(label): needs a template") }
            if r.patterns.isEmpty { problems.append("\(label): needs at least one pattern") }
            for p in r.patterns where (try? NSRegularExpression(pattern: p)) == nil {
                problems.append("\(label): invalid pattern \"\(p)\"")
            }
        }
        // Built-ins plus the user's own: a `deepLink` action naming anything else can never
        // fire. Skipped when the built-in pack didn't load (see CoreResources) — flagging every
        // deep-link rule as unknown would reject the whole config and take routing down with it.
        let builtins = RewriterStore.builtin().rewriters
        let builtinsLoaded = !builtins.isEmpty
        let knownRewriterIDs = Set(builtins.map(\.id) + config.customRewriters.map(\.id))

        for (i, rule) in config.rules.enumerated() {
            let label = "rule \(i + 1) (\(rule.name))"
            if case .deepLink(let id) = rule.action, builtinsLoaded, !knownRewriterIDs.contains(id) {
                problems.append("\(label): unknown deep-link app \"\(id)\"")
            }
            if rule.match.isEmpty {
                problems.append("\(label): needs at least one matcher (patterns, regex, or sourceApps)")
            }
            for p in rule.match.patterns where WildcardPattern(p) == nil {
                problems.append("\(label): invalid pattern \"\(p)\"")
            }
            if let r = rule.match.regex, (try? NSRegularExpression(pattern: r)) == nil {
                problems.append("\(label): invalid regex \"\(r)\"")
            }
            if let rw = rule.rewrite, (try? NSRegularExpression(pattern: rw.find)) == nil {
                problems.append("\(label): invalid rewrite regex \"\(rw.find)\"")
            }
            if case .open(let app, _) = rule.action, app.lowercased() == junctionBundleID {
                problems.append("\(label): action cannot target Junction itself (loop)")
            }
        }
        return problems
    }

    static func describeDecodingError(_ error: Error) -> String {
        if let d = error as? DecodingError {
            switch d {
            case .dataCorrupted(let ctx): return ctx.debugDescription
            case .keyNotFound(let key, let ctx):
                return "missing key \"\(key.stringValue)\" at \(path(ctx))"
            case .typeMismatch(_, let ctx): return "\(ctx.debugDescription) at \(path(ctx))"
            case .valueNotFound(_, let ctx): return "\(ctx.debugDescription) at \(path(ctx))"
            @unknown default: return String(describing: d)
            }
        }
        return String(describing: error)
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return p.isEmpty ? "root" : p
    }

    // MARK: Save

    /// Replaces the in-memory config and writes it to disk (creating directories as needed).
    public func save(_ newConfig: Config) throws {
        let problems = Self.validate(newConfig)
        guard problems.isEmpty else { throw ConfigError.invalid(problems) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(newConfig)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Only suppress when a watcher is armed — otherwise the flag would
        // swallow the user's first real external edit after startWatching().
        if watcher != nil { suppressNextReload = true }
        try data.write(to: fileURL, options: .atomic)
        config = newConfig
        lastError = nil
        onChange?(config)
    }

    /// Writes the current config if the file doesn't exist yet (first launch).
    public func bootstrapIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? save(config)
    }

    // MARK: Watch

    /// Starts watching the file for external edits. Invalid edits keep the last-good
    /// config in memory and surface `onError` (menu bar warning badge).
    public func startWatching() {
        watcher = FileWatcher(url: fileURL) { [weak self] in
            guard let self else { return }
            if self.suppressNextReload {
                self.suppressNextReload = false
                return
            }
            self.reload()
        }
        watcher?.start()
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    public func reload() {
        do {
            let fresh = try Self.load(from: fileURL)
            config = fresh
            lastError = nil
            onChange?(fresh)
        } catch let e as ConfigError {
            lastError = e
            onError?(e)
        } catch {
            let e = ConfigError.unreadable(String(describing: error))
            lastError = e
            onError?(e)
        }
    }
}
