import XCTest
@testable import JunctionCore

final class ConfigMirrorTests: XCTestCase {
    private var tmpDir: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var mirror: ConfigMirror!

    private let original = Data(#"{"fallback": {"app": "com.apple.Safari"}}"#.utf8)
    private let hereEdit = Data(#"{"fallback": {"app": "com.google.Chrome"}}"#.utf8)
    private let thereEdit = Data(#"{"fallback": {"app": "org.mozilla.firefox"}}"#.utf8)
    private let broken = Data("{ not json".utf8)

    private var localURL: URL { tmpDir.appendingPathComponent("local/config.json") }
    private var backupURL: URL { tmpDir.appendingPathComponent("local/config.backup.json") }
    private var drive: URL { tmpDir.appendingPathComponent("drive") }
    private var remoteURL: URL { mirror.remoteURL }

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("junction-mirror-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        suite = "junction-mirror-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        mirror = ConfigMirror(localURL: localURL, drive: drive, defaults: defaults)
        try write(original, to: localURL)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func remoteState() -> ConfigMirror.RemoteState {
        let done = expectation(description: "checked")
        var result: ConfigMirror.RemoteState?
        mirror.checkRemote { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result!
    }

    private func enable(from source: ConfigMirror.Source) -> String? {
        let done = expectation(description: "enabled")
        var failure: String?
        mirror.enable(from: source) { failure = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return failure
    }

    private func reconcile() {
        mirror.reconcile()
        mirror.queue.sync {}
    }

    private func setUpSynced() throws {
        XCTAssertNil(enable(from: .thisMac))
    }

    // MARK: Decisions

    func testStep() {
        let a = Data("a".utf8), b = Data("b".utf8), c = Data("c".utf8)
        XCTAssertEqual(ConfigMirror.step(local: a, remote: a, lastSynced: b, remoteIsNewer: false), .none, "identical copies end the echo")
        XCTAssertEqual(ConfigMirror.step(local: a, remote: b, lastSynced: b, remoteIsNewer: true), .push, "only this Mac changed, whatever the dates say")
        XCTAssertEqual(ConfigMirror.step(local: a, remote: b, lastSynced: a, remoteIsNewer: false), .pull, "only iCloud changed, whatever the dates say")
        XCTAssertEqual(ConfigMirror.step(local: a, remote: b, lastSynced: c, remoteIsNewer: true), .pull, "both changed: newer wins")
        XCTAssertEqual(ConfigMirror.step(local: a, remote: b, lastSynced: c, remoteIsNewer: false), .push, "both changed: newer wins")
        XCTAssertEqual(ConfigMirror.step(local: nil, remote: b, lastSynced: c, remoteIsNewer: false), .pull, "a lost local file is restored")
    }

    // MARK: Turning on

    func testRemoteStates() throws {
        XCTAssertEqual(remoteState(), .missing)
        try write(original, to: remoteURL)
        XCTAssertEqual(remoteState(), .matches)
        try write(thereEdit, to: remoteURL)
        XCTAssertEqual(remoteState(), .differs)
        try write(broken, to: remoteURL)
        guard case .invalid = remoteState() else { return XCTFail("a broken iCloud copy must not look usable") }
    }

    func testICloudDriveOffIsUnreadableNotMissing() throws {
        // "Missing" would offer to upload into a folder that isn't synced.
        try FileManager.default.removeItem(at: drive)
        guard case .unreadable = remoteState() else { return XCTFail("expected unreadable") }
    }

    func testEnableUploadsThisMacsBytes() throws {
        let commented = Data("{ // hand-written note\n \"fallback\": {\"app\": \"com.apple.Safari\"} }".utf8)
        try write(commented, to: localURL)
        XCTAssertNil(enable(from: .thisMac))
        XCTAssertEqual(try read(remoteURL), commented, "copied as bytes, so comments survive")
        XCTAssertTrue(mirror.isEnabled)
    }

    func testEnableFromICloudBacksUpThisMacsRules() throws {
        try write(thereEdit, to: remoteURL)
        XCTAssertNil(enable(from: .iCloud))
        XCTAssertEqual(try read(localURL), thereEdit)
        XCTAssertEqual(try read(backupURL), original)
    }

    func testEnableReplacingICloudBacksItUp() throws {
        try write(thereEdit, to: remoteURL)
        XCTAssertNil(enable(from: .thisMac))
        XCTAssertEqual(try read(remoteURL), original)
        XCTAssertEqual(try read(backupURL), thereEdit)
    }

    func testEnableRefusesAnInvalidSource() throws {
        try write(broken, to: localURL)
        XCTAssertNotNil(enable(from: .thisMac))
        XCTAssertFalse(exists(remoteURL))
        XCTAssertFalse(mirror.isEnabled)
    }

    // MARK: Syncing

    func testNothingHappensWhileOff() throws {
        try write(thereEdit, to: remoteURL)
        reconcile()
        XCTAssertEqual(try read(localURL), original)
    }

    func testLocalEditIsPushed() throws {
        try setUpSynced()
        try write(hereEdit, to: localURL)
        reconcile()
        XCTAssertEqual(try read(remoteURL), hereEdit)
    }

    func testRemoteEditIsPulledAndThePreviousRulesBackedUp() throws {
        try setUpSynced()
        try write(thereEdit, to: remoteURL)
        reconcile()
        XCTAssertEqual(try read(localURL), thereEdit)
        XCTAssertEqual(try read(backupURL), original)
    }

    func testRepeatedReconcileSettles() throws {
        try setUpSynced()
        try write(thereEdit, to: remoteURL)
        reconcile()
        try FileManager.default.removeItem(at: backupURL)
        reconcile()
        XCTAssertFalse(exists(backupURL), "nothing left to copy, so nothing gets overwritten")
    }

    func testConcurrentEditsKeepTheLoserInTheBackup() throws {
        try setUpSynced()
        try write(hereEdit, to: localURL)
        try write(thereEdit, to: remoteURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: remoteURL.path)
        reconcile()
        XCTAssertEqual(try read(remoteURL), hereEdit, "this Mac's edit is newer")
        XCTAssertEqual(try read(backupURL), thereEdit)
    }

    func testInvalidRemoteIsNotPulled() throws {
        try setUpSynced()
        try write(broken, to: remoteURL)
        let reported = expectation(description: "problem reported")
        mirror.onProblem = { if $0 != nil { reported.fulfill() } }
        reconcile()
        wait(for: [reported], timeout: 5)
        XCTAssertEqual(try read(localURL), original)
    }

    func testInvalidLocalEditStaysOnThisMac() throws {
        try setUpSynced()
        try write(broken, to: localURL)
        reconcile()
        XCTAssertEqual(try read(remoteURL), original)
    }

    func testMissingRemoteIsNotRecreated() throws {
        try setUpSynced()
        try FileManager.default.removeItem(at: remoteURL)
        try write(hereEdit, to: localURL)
        let reported = expectation(description: "problem reported")
        mirror.onProblem = { if $0 != nil { reported.fulfill() } }
        reconcile()
        wait(for: [reported], timeout: 5)
        XCTAssertFalse(exists(remoteURL), "it may have been deleted on purpose, or iCloud may be signed out")
    }

    /// The app skips first-launch bootstrap while sync is on, so this is what a wiped Mac hits.
    func testLostLocalFileIsRestoredFromICloud() throws {
        try setUpSynced()
        try FileManager.default.removeItem(at: localURL)
        reconcile()
        XCTAssertEqual(try read(localURL), original)
    }

    func testPullWritesThroughASymlinkedConfig() throws {
        let dotfile = tmpDir.appendingPathComponent("dotfiles/config.json")
        try write(original, to: dotfile)
        try FileManager.default.removeItem(at: localURL)
        try FileManager.default.createSymbolicLink(at: localURL, withDestinationURL: dotfile)
        try setUpSynced()
        try write(thereEdit, to: remoteURL)
        reconcile()
        XCTAssertEqual(try read(dotfile), thereEdit)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: localURL.path))
    }

    func testPullLeavesADanglingLinkAlone() throws {
        try setUpSynced()
        let gone = tmpDir.appendingPathComponent("dotfiles/config.json")
        try FileManager.default.removeItem(at: localURL)
        try FileManager.default.createSymbolicLink(at: localURL, withDestinationURL: gone)
        try write(thereEdit, to: remoteURL)
        let reported = expectation(description: "problem reported")
        mirror.onProblem = { if $0 != nil { reported.fulfill() } }
        reconcile()
        wait(for: [reported], timeout: 5)
        XCTAssertNotNil(
            try? FileManager.default.destinationOfSymbolicLink(atPath: localURL.path),
            "replacing the link with a plain file would quietly detach it from the dotfiles repo"
        )
    }

    func testMatchingCopyKeepsTheExistingBackup() throws {
        try write(hereEdit, to: backupURL)
        try write(original, to: remoteURL)
        XCTAssertNil(enable(from: .thisMac))
        XCTAssertEqual(try read(backupURL), hereEdit, "nothing was replaced, so the older backup still matters")
    }

    func testDisableStopsSyncingAndLeavesTheICloudCopy() throws {
        try setUpSynced()
        mirror.disable()
        mirror.queue.sync {}
        XCTAssertFalse(mirror.isEnabled)
        try write(thereEdit, to: remoteURL)
        reconcile()
        XCTAssertEqual(try read(localURL), original)
    }
}
