#if canImport(AppKit)
import Foundation
import JunctionCore
import XCTest

@testable import JunctionApp

@MainActor
final class ICloudSyncTests: XCTestCase {
    private var tmpDir: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var state: AppState!
    private var mirror: ConfigMirror!

    private let thisMac = Data(#"{"fallback": {"app": "com.apple.Safari"}}"#.utf8)
    private let elsewhere = Data(#"{"fallback": {"app": "org.mozilla.firefox"}}"#.utf8)

    private var localURL: URL { tmpDir.appendingPathComponent("local/config.json") }
    private var drive: URL { tmpDir.appendingPathComponent("drive") }
    private var remoteURL: URL { drive.appendingPathComponent("Junction/config.json") }

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("junction-icloud-\(UUID().uuidString)")
        suite = "junction-icloud-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        try write(thisMac, to: localURL)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        mirror = ConfigMirror(localURL: localURL, drive: drive, defaults: defaults)
        state = AppState(configStore: ConfigStore(fileURL: localURL), configMirror: mirror)
    }

    override func tearDown() async throws {
        mirror.stopWatching()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testFirstMacConfirmsBeforeUploading() throws {
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncChoice != nil }
        XCTAssertEqual(state.iCloudSyncChoice?.canUseICloud, false)
        XCTAssertFalse(state.iCloudSyncOn, "nothing happens until the user confirms")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remoteURL.path))

        state.finishTurningOnICloudSync(keeping: .thisMac)
        waitUntil { state.iCloudSyncOn }
        XCTAssertEqual(try Data(contentsOf: remoteURL), thisMac)
    }

    func testSecondMacChoosesWhichRulesToKeep() throws {
        try write(elsewhere, to: remoteURL)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncChoice != nil }
        XCTAssertEqual(state.iCloudSyncChoice?.canUseICloud, true)

        state.finishTurningOnICloudSync(keeping: .iCloud)
        waitUntil { state.iCloudSyncOn }
        XCTAssertEqual(try Data(contentsOf: localURL), elsewhere)
    }

    func testBrokenICloudCopyCanOnlyBeReplaced() throws {
        try write(Data("{ not json".utf8), to: remoteURL)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncChoice != nil }
        XCTAssertEqual(state.iCloudSyncChoice?.canUseICloud, false)
    }

    func testMatchingCopyTurnsOnWithoutAsking() throws {
        try write(thisMac, to: remoteURL)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncOn }
        XCTAssertNil(state.iCloudSyncChoice)
    }

    func testICloudDriveOffExplainsAndStaysOff() throws {
        try FileManager.default.removeItem(at: drive)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncProblem != nil }
        XCTAssertFalse(state.iCloudSyncOn)
        XCTAssertNil(state.iCloudSyncChoice)
    }

    func testTurningOffKeepsTheICloudCopy() throws {
        try write(thisMac, to: remoteURL)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncOn }
        state.turnOffICloudSync()
        XCTAssertFalse(state.iCloudSyncOn)
        waitUntil { !mirror.isEnabled }
        XCTAssertTrue(FileManager.default.fileExists(atPath: remoteURL.path))
    }

    /// The whole loop: a Settings save reaches iCloud without anything else calling sync.
    func testSavingARuleReachesICloud() throws {
        try write(thisMac, to: remoteURL)
        state.turnOnICloudSync()
        waitUntil { state.iCloudSyncOn }
        state.updateConfig { $0.fallback = Fallback(app: "com.google.Chrome") }
        waitUntil {
            (try? ConfigStore.load(from: remoteURL))?.fallback.app == "com.google.Chrome"
        }
    }
}
#endif
