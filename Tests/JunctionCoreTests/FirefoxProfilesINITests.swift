import XCTest
@testable import JunctionCore

final class FirefoxProfilesINITests: XCTestCase {
    /// A real profiles.ini: sections out of order, a legacy Default=1, and an [Install…]
    /// section whose Default= points at a different profile than the legacy flag.
    private let real = """
    [Profile1]
    Name=default
    IsRelative=1
    Path=Profiles/o49sjw1y.default
    Default=1

    [Profile0]
    Name=default-release
    IsRelative=1
    Path=Profiles/1hmaiaqc.default-release

    [General]
    StartWithLastProfile=1
    Version=2

    [Install2656FF1E876E9973]
    Default=Profiles/1hmaiaqc.default-release
    Locked=1
    """

    func testParsesProfilesSortedByName() {
        let entries = FirefoxProfilesINI.parse(real)
        XCTAssertEqual(entries.map(\.name), ["default", "default-release"])
        XCTAssertEqual(entries[1].path, "Profiles/1hmaiaqc.default-release")
        XCTAssertTrue(entries[0].isRelative)
    }

    /// [General] and [Install…] carry Default=/Path= keys that must not become profiles.
    func testIgnoresNonProfileSections() {
        XCTAssertEqual(FirefoxProfilesINI.parse(real).count, 2)
    }

    func testAbsolutePathProfile() {
        let entries = FirefoxProfilesINI.parse("""
        [Profile0]
        Name=Work
        IsRelative=0
        Path=/Volumes/External/ff-work
        """)
        XCTAssertEqual(entries, [FirefoxProfileEntry(name: "Work", path: "/Volumes/External/ff-work", isRelative: false)])
    }

    func testSkipsSectionMissingNameOrPath() {
        let entries = FirefoxProfilesINI.parse("""
        [Profile0]
        Path=Profiles/orphan

        [Profile1]
        Name=Good
        Path=Profiles/good
        """)
        XCTAssertEqual(entries.map(\.name), ["Good"])
    }

    func testIgnoresCommentsAndBlankLines() {
        let entries = FirefoxProfilesINI.parse("""
        ; a comment
        # another

        [Profile0]
        Name=Solo
        Path=Profiles/solo
        """)
        XCTAssertEqual(entries.map(\.name), ["Solo"])
    }

    func testEmptyFileYieldsNoProfiles() {
        XCTAssertTrue(FirefoxProfilesINI.parse("").isEmpty)
    }
}
