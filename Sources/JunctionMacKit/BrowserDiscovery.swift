#if canImport(AppKit)
import AppKit
import Foundation

public struct Browser: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let appURL: URL
    public let profiles: [BrowserProfile]

    public var isChromium: Bool { !profiles.isEmpty || ChromiumProfiles.dataDirectories[bundleID] != nil }
}

public struct BrowserProfile: Identifiable, Hashable, Sendable {
    /// Chromium profile directory name, e.g. "Default" or "Profile 1".
    public let directory: String
    /// Human-readable name from Local State, e.g. "Work".
    public let displayName: String
    public var id: String { directory }
}

/// Finds installed browsers and their Chromium profiles.
public enum BrowserDiscovery {
    /// All apps registered as handlers for https URLs, excluding Junction itself.
    public static func installedBrowsers() -> [Browser] {
        let https = URL(string: "https://example.com")!
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: https)
        var seen = Set<String>()
        var browsers: [Browser] = []
        for appURL in urls {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier,
                  bundleID.lowercased() != "com.jnahian.junction",
                  !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            browsers.append(Browser(
                bundleID: bundleID,
                name: name,
                appURL: appURL,
                profiles: ChromiumProfiles.profiles(for: bundleID)
            ))
        }
        return browsers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Whether any installed app claims this URL scheme (used for deep-link gating).
    public static func isSchemeHandled(_ scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://probe") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }
}

/// Reads Chromium `Local State` files to discover profiles (F5).
public enum ChromiumProfiles {
    /// bundle ID → data directory under ~/Library/Application Support.
    public static let dataDirectories: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]

    public static func profiles(for bundleID: String) -> [BrowserProfile] {
        guard let dir = dataDirectories[bundleID] else { return [] }
        let localState = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(dir)
            .appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return []
        }
        return infoCache.compactMap { key, value -> BrowserProfile? in
            let info = value as? [String: Any]
            let name = (info?["name"] as? String) ?? key
            return BrowserProfile(directory: key, displayName: name)
        }
        .sorted { l, r in
            // "Default" first, then "Profile N" numerically, then alphabetical.
            if l.directory == "Default" { return true }
            if r.directory == "Default" { return false }
            return l.directory.localizedStandardCompare(r.directory) == .orderedAscending
        }
    }
}
#endif
