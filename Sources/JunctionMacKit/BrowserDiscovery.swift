#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore

/// How a browser wants to be told which profile to use. Derived from the bundle ID, never
/// inferred from whether profiles were found: a Firefox with profiles is still not Chromium.
public enum BrowserFamily: Sendable {
    case chromium
    case firefox
    /// Safari, Orion, anything else: no supported profile switching.
    case other
}

public struct Browser: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let appURL: URL
    public let profiles: [BrowserProfile]

    public var family: BrowserFamily { BrowserDiscovery.family(forBundleID: bundleID) }
}

public struct BrowserProfile: Identifiable, Hashable, Sendable {
    /// The token the browser's launch flag takes: a Chromium profile directory ("Profile 1")
    /// or a Firefox profile name ("default-release"). This is what a rule's `profile` field holds.
    public let directory: String
    /// Human-readable name, e.g. "Work". Equals `directory` for Firefox, which has no separate label.
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
                profiles: profiles(forBundleID: bundleID)
            ))
        }
        return browsers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func family(forBundleID bundleID: String) -> BrowserFamily {
        if ChromiumProfiles.dataDirectories[bundleID] != nil { return .chromium }
        if FirefoxProfiles.dataDirectories[bundleID] != nil { return .firefox }
        return .other
    }

    public static func profiles(forBundleID bundleID: String) -> [BrowserProfile] {
        switch family(forBundleID: bundleID) {
        case .chromium: return ChromiumProfiles.profiles(for: bundleID)
        case .firefox: return FirefoxProfiles.profiles(for: bundleID)
        case .other: return []
        }
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

/// Reads Firefox's `profiles.ini` to discover profiles.
public enum FirefoxProfiles {
    /// bundle ID → data directory under ~/Library/Application Support. Forks (LibreWolf,
    /// Waterfox, Dev Edition) drop in here once someone can test them.
    public static let dataDirectories: [String: String] = [
        "org.mozilla.firefox": "Firefox",
    ]

    public static func profiles(for bundleID: String) -> [BrowserProfile] {
        guard let dir = dataDirectories[bundleID] else { return [] }
        let ini = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(dir)
            .appendingPathComponent("profiles.ini")
        guard let text = try? String(contentsOf: ini, encoding: .utf8) else { return [] }
        // `-P` takes the profile *name*, so that's the token a rule stores.
        return FirefoxProfilesINI.parse(text).map {
            BrowserProfile(directory: $0.name, displayName: $0.name)
        }
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
