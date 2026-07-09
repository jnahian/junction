import Foundation

/// A deep-link rewriter: turns an https URL into a native app scheme URL.
/// Definitions ship as data (`rewriters.json`) so contributions don't require Swift.
public struct Rewriter: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Regex over the full URL string. First matching pattern wins.
    public let patterns: [String]
    /// Template with `$1`…`$9` capture references. Empty groups substitute as "".
    public let template: String
    /// URL scheme of the target app, used to check installation (e.g. "zoommtg").
    public let scheme: String
    /// Bundle ID hint for nicer UI (optional).
    public let bundleID: String?

    public init(id: String, name: String, patterns: [String], template: String, scheme: String, bundleID: String? = nil) {
        self.id = id
        self.name = name
        self.patterns = patterns
        self.template = template
        self.scheme = scheme
        self.bundleID = bundleID
    }

    /// Applies the rewriter. Returns nil when no pattern matches or the result isn't a valid URL.
    public func rewrite(_ url: URL) -> URL? {
        let s = url.absoluteString
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: s, options: [], range: range) else { continue }
            var out = ""
            var i = template.startIndex
            while i < template.endIndex {
                let ch = template[i]
                if ch == "$", template.index(after: i) < template.endIndex,
                   let digit = template[template.index(after: i)].wholeNumberValue, digit >= 1, digit <= 9 {
                    if digit < match.numberOfRanges, match.range(at: digit).location != NSNotFound,
                       let r = Range(match.range(at: digit), in: s) {
                        out += s[r]
                    }
                    i = template.index(i, offsetBy: 2)
                } else {
                    out.append(ch)
                    i = template.index(after: i)
                }
            }
            out = Self.cleanEmptyParams(out)
            if let result = URL(string: out) { return result }
        }
        return nil
    }

    /// Removes query params whose value ended up empty after substitution
    /// (e.g. `&pwd=` when the source URL had no password), plus dangling `?`/`&`.
    static func cleanEmptyParams(_ s: String) -> String {
        guard let qIndex = s.firstIndex(of: "?") else { return s }
        let base = String(s[..<qIndex])
        let query = String(s[s.index(after: qIndex)...])
        let kept = query.split(separator: "&").filter { pair in
            if let eq = pair.firstIndex(of: "=") {
                return pair.index(after: eq) < pair.endIndex
            }
            return !pair.isEmpty
        }
        return kept.isEmpty ? base : base + "?" + kept.joined(separator: "&")
    }
}

/// Loads and queries the bundled rewriter pack.
public struct RewriterStore: Sendable {
    public let rewriters: [Rewriter]

    public init(rewriters: [Rewriter]) {
        self.rewriters = rewriters
    }

    /// Loads `rewriters.json` from the module bundle.
    public static func builtin() -> RewriterStore {
        struct FileFormat: Decodable {
            var version: Int
            var rewriters: [Rewriter]
        }
        guard let url = CoreResources.url(forResource: "rewriters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(FileFormat.self, from: data) else {
            return RewriterStore(rewriters: [])
        }
        return RewriterStore(rewriters: parsed.rewriters)
    }

    public func rewriter(id: String) -> Rewriter? {
        rewriters.first { $0.id == id }
    }
}
