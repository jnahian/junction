import Foundation

/// Wildcard pattern per Appendix A of the PRD, pre-compiled to a regex.
///
/// Semantics:
/// - Matched against `host/path`; scheme ignored unless the pattern explicitly contains `://`.
/// - `*` matches within a segment (host label / path segment); `**` or a *trailing* `*` matches across segments.
/// - Bare domain (`github.com`) matches the domain and all subpaths.
/// - `*.github.com` matches subdomains *and* the apex domain.
/// - Host is case-insensitive, path is case-sensitive. Query string is ignored.
public struct WildcardPattern: @unchecked Sendable, Equatable {
    public let source: String
    private let schemeRegex: NSRegularExpression?
    private let hostRegex: NSRegularExpression
    private let pathRegex: NSRegularExpression?

    public init?(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        source = trimmed

        var rest = trimmed
        var schemePart: String? = nil
        if let range = rest.range(of: "://") {
            schemePart = String(rest[..<range.lowerBound])
            rest = String(rest[range.upperBound...])
        }

        let hostPart: String
        let pathPart: String?
        if let slash = rest.firstIndex(of: "/") {
            hostPart = String(rest[..<slash])
            pathPart = String(rest[rest.index(after: slash)...]) // path without leading slash
        } else {
            hostPart = rest
            pathPart = nil
        }
        guard !hostPart.isEmpty else { return nil }

        do {
            if let s = schemePart {
                schemeRegex = try NSRegularExpression(
                    pattern: "^" + Self.translate(s, segmentSeparator: nil, isLast: true) + "$",
                    options: [.caseInsensitive]
                )
            } else {
                schemeRegex = nil
            }

            var hostPattern: String
            if hostPart == "*" || hostPart == "**" {
                hostPattern = ".*"
            } else if hostPart.hasPrefix("*.") {
                // `*.example.com` → any chain of subdomains, apex included.
                let base = String(hostPart.dropFirst(2))
                hostPattern = "(?:[^.]+\\.)*" + Self.translate(base, segmentSeparator: ".", isLast: true)
            } else {
                hostPattern = Self.translate(hostPart, segmentSeparator: ".", isLast: true)
            }
            hostRegex = try NSRegularExpression(pattern: "^" + hostPattern + "$", options: [.caseInsensitive])

            if let p = pathPart {
                if p.isEmpty || p == "*" || p == "**" {
                    pathRegex = nil // `example.com/` or `example.com/*` → any path
                } else {
                    pathRegex = try NSRegularExpression(pattern: "^" + Self.translatePath(p) + "$", options: [])
                }
            } else {
                pathRegex = nil // bare domain → all subpaths
            }
        } catch {
            return nil
        }
    }

    /// Translate one wildcard component to regex. `*` → within-segment wildcard.
    private static func translate(_ component: String, segmentSeparator: Character?, isLast: Bool) -> String {
        var regex = ""
        for ch in component {
            switch ch {
            case "*":
                if let sep = segmentSeparator {
                    regex += "[^\(NSRegularExpression.escapedPattern(for: String(sep)))]*"
                } else {
                    regex += ".*"
                }
            default:
                regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        return regex
    }

    /// Translate a path pattern: `**` crosses segments, `*` stays in a segment,
    /// a trailing `*` also crosses segments.
    private static func translatePath(_ path: String) -> String {
        var regex = ""
        let chars = Array(path)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "*" {
                let isDouble = i + 1 < chars.count && chars[i + 1] == "*"
                let isTrailing = (isDouble && i + 2 == chars.count) || (!isDouble && i + 1 == chars.count)
                if isDouble {
                    regex += ".*"
                    i += 2
                } else if isTrailing {
                    regex += ".*"
                    i += 1
                } else {
                    regex += "[^/]*"
                    i += 1
                }
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(ch))
                i += 1
            }
        }
        return regex
    }

    public func matches(_ url: URL) -> Bool {
        if let schemeRegex {
            let scheme = url.scheme ?? ""
            guard schemeRegex.wholeMatch(scheme) else { return false }
        }
        guard let host = url.host, hostRegex.wholeMatch(host) else { return false }
        if let pathRegex {
            var path = url.path
            if path.hasPrefix("/") { path.removeFirst() }
            guard pathRegex.wholeMatch(path) else { return false }
        }
        return true
    }

    public static func == (lhs: WildcardPattern, rhs: WildcardPattern) -> Bool {
        lhs.source == rhs.source
    }
}

extension NSRegularExpression {
    func wholeMatch(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return firstMatch(in: s, options: [], range: range) != nil
    }
}
