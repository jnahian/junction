#if canImport(AppKit)
import AppKit
import SwiftUI

/// AppKit material blur — the "glass" backdrop used by the picker HUD and onboarding.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

/// HIG-standard metrics so every surface uses the same rhythm.
enum Metrics {
    /// Window content inset (Apple's standard 20 pt).
    static let windowPadding: CGFloat = 20
    /// Compact HUD/panel inset.
    static let panelPadding: CGFloat = 14
    /// Spacing between sibling controls.
    static let controlSpacing: CGFloat = 8
    /// Spacing between sections/groups.
    static let sectionSpacing: CGFloat = 12
    /// Continuous corner radius for floating panels.
    static let panelCornerRadius: CGFloat = 14
    /// Continuous corner radius for selection highlights inside panels.
    static let rowCornerRadius: CGFloat = 7
}

extension NSMenuItem {
    /// Attach a template SF Symbol, sized like system menu items.
    func withSymbol(_ name: String) -> NSMenuItem {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return self
    }
}
#endif
