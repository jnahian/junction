import Foundation

/// Anchor class so `Bundle(for:)` resolves to wherever this module's binary lives
/// (the .xctest bundle under `swift test`, the app binary in Junction.app, etc.).
private final class BundleFinder {}

/// Locates the SPM resource bundle without the generated `Bundle.module` accessor,
/// which `fatalError`s when the bundle isn't found (fatal for the CLI installed
/// outside the app bundle). Mirrors SPM's own candidate list, plus the CLI layout.
///
/// Covered deployment shapes:
/// - `swift test` / `swift run` on macOS and Linux (Bundle(for:) / executable dir)
/// - JunctionCore linked into Junction.app (Bundle.main.resourceURL)
/// - the CLI at `Junction.app/Contents/Helpers/junction` (../Resources)
///
/// Note: Darwin names the artifact `.bundle`; other platforms use `.resources`.
enum CoreResources {
    static let bundle: Bundle? = {
        let bundleNames = ["Junction_JunctionCore.bundle", "Junction_JunctionCore.resources"]

        let anchor = Bundle(for: BundleFinder.self)
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }
        if let url = anchor.resourceURL { candidates.append(url) }
        candidates.append(Bundle.main.bundleURL)
        candidates.append(anchor.bundleURL)
        // Under `swift test` on macOS the module lives inside JunctionPackageTests.xctest,
        // but SPM puts resource bundles NEXT TO the .xctest, in .build/debug — check parents.
        candidates.append(anchor.bundleURL.deletingLastPathComponent())
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let dir = executable.deletingLastPathComponent()
            candidates.append(dir)
            candidates.append(dir.deletingLastPathComponent().appendingPathComponent("Resources"))
        }

        for candidate in candidates {
            for name in bundleNames {
                let path = candidate.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: path.path),
                   let bundle = Bundle(url: path) {
                    return bundle
                }
            }
        }
        return nil
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle?.url(forResource: name, withExtension: ext)
    }
}
