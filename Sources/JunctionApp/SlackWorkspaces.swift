import Foundation

/// Slack's scheme takes team IDs and its permalinks carry only the subdomain, so a mapping has to
/// come from somewhere. The desktop app already knows both for every workspace you're signed into.
///
/// ponytail: reads Slack's undocumented state file, so a Slack update can move or reshape it. Every
/// failure returns an empty map — the workspace stays unmapped and its links open in the browser,
/// same as before — and the config file is always there as the manual escape hatch.
enum SlackWorkspaces {
    private static let statePaths = [
        "Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/storage/root-state.json",
        "Library/Application Support/Slack/storage/root-state.json",
    ]

    private struct State: Decodable {
        struct Workspace: Decodable {
            let id: String
            let domain: String
        }
        /// Keyed by team ID; the value repeats it alongside the subdomain.
        let workspaces: [String: Workspace]
    }

    /// Subdomain → team ID for every workspace the Slack app is signed into.
    static func all() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in statePaths {
            guard let data = try? Data(contentsOf: home.appending(path: path)),
                  let state = try? JSONDecoder().decode(State.self, from: data) else { continue }
            return Dictionary(state.workspaces.values.map { ($0.domain, $0.id) },
                              uniquingKeysWith: { first, _ in first })
        }
        return [:]
    }
}
