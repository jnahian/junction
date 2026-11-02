import Foundation

/// Keeps a copy of `config.json` in iCloud Drive. Routing and the CLI never read that copy: the
/// local file stays real, so iCloud being slow, offline or signed out can only leave the rules
/// stale, and a link that launches the app never waits on a download.
///
/// Files are copied as bytes, so comments survive, and two identical copies end the echo between
/// this Mac's watchers. The last synced contents are kept per Mac in `defaults`: they tell an edit
/// made here from one made elsewhere, and their presence means sync is on.
public final class ConfigMirror: @unchecked Sendable {
    public enum RemoteState: Equatable {
        case missing
        case matches
        case differs
        case invalid(String)
        case unreadable(String)
    }

    public enum Source { case thisMac, iCloud }

    enum Step: Equatable { case none, push, pull }

    public static let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    private static let lastSyncedKey = "iCloudSyncLastSynced"

    /// Called on the main thread with what's stopping sync, or nil once it's working.
    public var onProblem: ((String?) -> Void)?

    let remoteURL: URL
    /// Everything that touches iCloud runs here: reading an evicted file blocks on its download.
    let queue = DispatchQueue(label: "com.jnahian.junction.configmirror")

    private let localURL: URL
    private let drive: URL
    private let defaults: UserDefaults
    private var watcher: FileWatcher?

    public init(localURL: URL, drive: URL = ConfigMirror.iCloudDrive, defaults: UserDefaults = .standard) {
        self.localURL = localURL
        self.drive = drive
        self.defaults = defaults
        self.remoteURL = drive.appendingPathComponent("Junction/config.json")
    }

    public var isEnabled: Bool { defaults.data(forKey: Self.lastSyncedKey) != nil }

    private var backupURL: URL { localURL.deletingLastPathComponent().appendingPathComponent("config.backup.json") }

    // MARK: Turning sync on and off

    /// Looks at the iCloud copy before sync starts. The first read of an evicted file is what
    /// triggers macOS's iCloud Drive prompt, so this is where the user should meet it.
    public func checkRemote(completion: @escaping (RemoteState) -> Void) {
        queue.async {
            let state = self.remoteState()
            DispatchQueue.main.async { completion(state) }
        }
    }

    /// Makes `source` the first synced version. The side it replaces goes to the backup file.
    public func enable(from source: Source, completion: @escaping (String?) -> Void) {
        queue.async {
            var failure: String?
            do {
                let (from, to) = source == .thisMac ? (self.localURL, self.remoteURL) : (self.remoteURL, self.localURL)
                let kept = try Data(contentsOf: from)
                _ = try ConfigStore.decode(kept)
                if let replaced = try? Data(contentsOf: to), replaced != kept { try self.backUp(replaced) }
                try ConfigStore.write(kept, to: to)
                self.defaults.set(kept, forKey: Self.lastSyncedKey)
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async { completion(failure) }
        }
    }

    /// Stops syncing this Mac. The iCloud copy stays, since other Macs may still use it.
    public func disable() {
        stopWatching()
        queue.async { self.defaults.removeObject(forKey: Self.lastSyncedKey) }
    }

    private func remoteState() -> RemoteState {
        guard FileManager.default.fileExists(atPath: drive.path) else {
            return .unreadable("iCloud Drive is off. Turn it on in System Settings → Apple Account → iCloud.")
        }
        let remote: Data
        do {
            remote = try Data(contentsOf: remoteURL)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable("Can't read iCloud Drive: \(error.localizedDescription) Check System Settings → Privacy & Security → Files and Folders.")
        }
        do {
            _ = try ConfigStore.decode(remote)
        } catch {
            return .invalid(error.localizedDescription)
        }
        return remote == (try? Data(contentsOf: localURL)) ? .matches : .differs
    }

    // MARK: Syncing

    public func startWatching() {
        watcher = FileWatcher(url: remoteURL) { [weak self] in self?.reconcile() }
        watcher?.start()
        reconcile()
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// Brings the two copies back in line. Does nothing while sync is off.
    public func reconcile() {
        queue.async { self.reconcileNow() }
    }

    private func reconcileNow() {
        guard let lastSynced = defaults.data(forKey: Self.lastSyncedKey) else { return }
        // Missing here means deleted, or iCloud signed out. Writing it back from this Mac would
        // undo a deletion or leave a stray file in a folder that's no longer synced.
        guard let remote = try? Data(contentsOf: remoteURL) else {
            report("Junction's file in iCloud Drive is missing. Turn sync off and on again to upload this Mac's rules.")
            return
        }
        let local = try? Data(contentsOf: localURL)
        let remoteIsNewer = Self.modified(remoteURL) > Self.modified(localURL)
        do {
            switch Self.step(local: local, remote: remote, lastSynced: lastSynced, remoteIsNewer: remoteIsNewer) {
            case .none:
                defaults.set(remote, forKey: Self.lastSyncedKey)
            case .push:
                // An invalid local edit already has its menu-bar warning. It stays on this Mac.
                guard let local, (try? ConfigStore.decode(local)) != nil else { return }
                if remote != lastSynced { try backUp(remote) }
                try ConfigStore.write(local, to: remoteURL)
                defaults.set(local, forKey: Self.lastSyncedKey)
            case .pull:
                do {
                    _ = try ConfigStore.decode(remote)
                } catch {
                    report("The copy in iCloud Drive has a problem, so this Mac kept its rules. \(error.localizedDescription)")
                    return
                }
                if let local { try backUp(local) }
                // ConfigStore's watcher sees this and reloads, the same as any external edit.
                try ConfigStore.write(remote, to: localURL)
                defaults.set(remote, forKey: Self.lastSyncedKey)
            }
            report(nil)
        } catch {
            report("Couldn't sync with iCloud Drive: \(error.localizedDescription)")
        }
    }

    /// Three-way comparison against the last synced contents. A side that still matches it hasn't
    /// changed, so the other side's edit wins; when both changed, the newer file does.
    static func step(local: Data?, remote: Data, lastSynced: Data, remoteIsNewer: Bool) -> Step {
        guard let local else { return .pull }
        if local == remote { return .none }
        if remote == lastSynced { return .push }
        if local == lastSynced { return .pull }
        return remoteIsNewer ? .pull : .push
    }

    private func backUp(_ data: Data) throws {
        try ConfigStore.write(data, to: backupURL)
    }

    private func report(_ problem: String?) {
        DispatchQueue.main.async { self.onProblem?(problem) }
    }

    private static func modified(_ url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }
}
