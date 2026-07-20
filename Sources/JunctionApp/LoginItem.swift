import ServiceManagement

extension SMAppService {
    /// Login-item registration keys on the bundle's on-disk path, so a copy run from
    /// ~/Downloads or a dev `dist/` folder registers as a *separate* startup item next to
    /// the real /Applications install. Only let the app register itself when it lives in
    /// /Applications, so stray copies can't create duplicate login items.
    /// ponytail: /Applications only; widen to ~/Applications if users install there.
    static var mainAppCanRegister: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }
}
