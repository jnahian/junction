import Foundation

/// Locates the SPM resource bundle (`Junction_JunctionCore.bundle`) without using the
/// generated `Bundle.module` accessor, which `fatalError`s when the bundle isn't found.
///
/// Search order covers every deployment shape:
/// - `Junction.app/Contents/Resources/` (JunctionCore linked into the app)
/// - next to the executable (`swift run`, `swift test`, `.build/release/`)
/// - `../Resources/` relative to the executable (the CLI at `Junction.app/Contents/Helpers/junction`)
enum CoreResources {
    static let bundle: Bundle? = {
        let name = "Junction_JunctionCore.bundle"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        candidates.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let dir = executable.deletingLastPathComponent()
            candidates.append(dir)
            candidates.append(dir.deletingLastPathComponent().appendingPathComponent("Resources"))
        }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate.appendingPathComponent(name)) {
                return bundle
            }
        }
        return nil
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle?.url(forResource: name, withExtension: ext)
    }
}
