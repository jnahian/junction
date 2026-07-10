import Foundation

/// One `[ProfileN]` entry from Firefox's `profiles.ini`.
public struct FirefoxProfileEntry: Equatable, Sendable {
    /// The name Firefox's `-P` flag takes, e.g. "default-release".
    public let name: String
    /// Profile directory, relative to the Firefox support dir when `isRelative`.
    public let path: String
    public let isRelative: Bool

    public init(name: String, path: String, isRelative: Bool) {
        self.name = name
        self.path = path
        self.isRelative = isRelative
    }
}

/// Parses Firefox's `profiles.ini`. Pure text in, entries out: no AppKit, no filesystem.
///
/// The file is INI-ish, not INI: only `[ProfileN]` sections describe profiles. `[General]`
/// and `[InstallXXXX]` sections are skipped, so the per-install default lives elsewhere and
/// is deliberately ignored — it decides which profile Firefox opens on its own, not where
/// Junction routes a link.
public enum FirefoxProfilesINI {
    public static func parse(_ ini: String) -> [FirefoxProfileEntry] {
        var entries: [FirefoxProfileEntry] = []
        var inProfileSection = false
        var name: String?
        var path: String?
        var isRelative = true

        func flush() {
            // Firefox needs both to be usable; a section missing either is malformed, skip it.
            if inProfileSection, let name, let path, !name.isEmpty, !path.isEmpty {
                entries.append(FirefoxProfileEntry(name: name, path: path, isRelative: isRelative))
            }
            name = nil
            path = nil
            isRelative = true
        }

        for rawLine in ini.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                flush()
                inProfileSection = line.hasPrefix("[Profile")
                continue
            }
            guard inProfileSection, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "Name": name = value
            case "Path": path = value
            case "IsRelative": isRelative = value == "1"
            default: break
            }
        }
        flush()

        // profiles.ini lists sections in arbitrary order (Profile1 often precedes Profile0).
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
