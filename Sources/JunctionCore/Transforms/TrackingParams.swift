import Foundation

/// Strips known tracking query parameters from URLs.
/// The built-in list ships as `tracking-params.json` (data, not code — PR-friendly).
public struct TrackingParamStripper: Sendable {
    /// Exact parameter names to remove.
    public let exactNames: Set<String>
    /// Prefixes: any param starting with one of these is removed (e.g. `utm_`).
    public let prefixes: [String]

    public init(exactNames: Set<String>, prefixes: [String]) {
        self.exactNames = exactNames
        self.prefixes = prefixes
    }

    /// Loads the built-in list from the bundled resource, merged with user extras.
    public static func builtin(extra: [String] = []) -> TrackingParamStripper {
        struct FileFormat: Decodable {
            var exact: [String]
            var prefixes: [String]
        }
        var exact: Set<String> = []
        var prefixes: [String] = []
        if let url = CoreResources.url(forResource: "tracking-params", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode(FileFormat.self, from: data) {
            exact = Set(parsed.exact.map { $0.lowercased() })
            prefixes = parsed.prefixes.map { $0.lowercased() }
        }
        for name in extra {
            let n = name.lowercased()
            if n.hasSuffix("*") {
                prefixes.append(String(n.dropLast()))
            } else {
                exact.insert(n)
            }
        }
        return TrackingParamStripper(exactNames: exact, prefixes: prefixes)
    }

    public func shouldStrip(_ name: String) -> Bool {
        let n = name.lowercased()
        if exactNames.contains(n) { return true }
        return prefixes.contains { n.hasPrefix($0) }
    }

    /// Returns the URL with tracking params removed. Everything else is preserved verbatim.
    public func strip(_ url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return url }
        let kept = items.filter { !shouldStrip($0.name) }
        guard kept.count != items.count else { return url }
        var mutable = components
        mutable.queryItems = kept.isEmpty ? nil : kept
        return mutable.url ?? url
    }
}
