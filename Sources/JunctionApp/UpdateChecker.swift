#if canImport(AppKit)
import AppKit
import Foundation

// Module-scoped: the menu bar and the General settings pane must share one checker,
// or each would run its own daily checks.
@MainActor let updateChecker = UpdateChecker()

/// Asks GitHub for the latest release at launch and once a day. Junction doesn't install
/// updates: a newer release puts a dot on the menu-bar icon and an "Update to X…" item
/// that opens the release page. This is the only network request Junction makes.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    /// The latest release, when it's newer than this build.
    @Published private(set) var available: Release?

    /// Nil under `swift run`, which has no Info.plist and so nothing to compare against.
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    // `/releases/latest` already skips drafts and prereleases.
    private static let latestURL = URL(string: "https://api.github.com/repos/jnahian/junction/releases/latest")!
    // No cookies or cache on disk.
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?
    private var lastChecked = Date.distantPast

    /// Background checks fail silently; the next one retries.
    func start() {
        guard currentVersion != nil, timer == nil else { return }
        Task { try? await refresh() }
        // Hourly against the wall clock rather than one 24-hour timer, whose interval may
        // not count time asleep: a laptop that sleeps overnight would check every few days.
        timer = .scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastChecked) >= 24 * 60 * 60 else { return }
                _ = try? await self.refresh()
            }
        }
    }

    /// "Check for Updates…" always answers, since a check that shows nothing looks broken.
    func checkNow() {
        Task {
            let alert = NSAlert()
            var release: Release?
            do {
                release = try await refresh()
                if let release {
                    alert.messageText = "Junction \(release.version) is available"
                    alert.informativeText = "You have \(currentVersion ?? "an older version"). Download the new version from its release page on GitHub."
                    alert.addButton(withTitle: "Download…")
                    alert.addButton(withTitle: "Later")
                } else {
                    alert.messageText = "Junction is up to date"
                    alert.informativeText = "\(currentVersion ?? "This") is the newest version."
                }
            } catch {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Junction couldn't reach GitHub. Check your connection and try again."
            }
            // LSUIElement apps aren't frontmost, so the alert would open behind everything.
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let release {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    @discardableResult
    private func refresh() async throws -> Release? {
        guard let currentVersion else { return nil }
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let latest = try JSONDecoder().decode(Release.self, from: data)
        lastChecked = Date()
        available = Self.isNewer(latest.version, than: currentVersion) ? latest : nil
        return available
    }

    /// Dotted components compare as numbers, so 0.10.0 is newer than 0.9.0.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }
}
#endif
