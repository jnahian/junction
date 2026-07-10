#if canImport(AppKit)
import AppKit
import Foundation
import JunctionMacKit
import SwiftUI

/// Floating, keyboard-first browser picker (F7): appears at the cursor,
/// `1–9` open, arrows+Return navigate, `Esc` = fallback, `⌘C` = copy.
@MainActor
final class PickerPanelController {
    private let state: AppState
    private var panel: NSPanel?

    init(state: AppState) {
        self.state = state
    }

    /// Flattened choices: every browser, plus one entry per Chromium profile.
    struct Choice: Identifiable {
        let id = UUID()
        let browser: Browser
        let profile: BrowserProfile?
        var title: String {
            profile.map { "\(browser.name) (\($0.displayName))" } ?? browser.name
        }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: browser.appURL.path) }
    }

    func show(for url: URL) {
        dismiss()
        state.refreshBrowsers()

        var choices: [Choice] = []
        for browser in state.browsers {
            choices.append(Choice(browser: browser, profile: nil))
            for profile in browser.profiles {
                choices.append(Choice(browser: browser, profile: profile))
            }
        }
        guard !choices.isEmpty else {
            state.openInFallback(url)
            return
        }

        let view = PickerView(
            url: url,
            choices: choices,
            onPick: { [weak self] choice in
                self?.state.open(url: url, in: choice.browser, profile: choice.profile)
                self?.dismiss()
            },
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.state.openInFallback(url)
                self?.dismiss()
            },
            onCreateRule: { [weak self] in
                self?.dismiss()
                self?.state.settingsPresenter?()
                NotificationCenter.default.post(
                    name: .junctionPrefillRule, object: nil,
                    userInfo: ["url": url]
                )
            }
        )

        let hosting = NSHostingController(rootView: view)
        // Borderless so the SwiftUI material shape *is* the window — glass edge to edge.
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        panel.setContentSize(hosting.view.fittingSize)

        // Appear at the cursor.
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 8)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            origin.x = max(screen.visibleFrame.minX + 8, min(origin.x, screen.visibleFrame.maxX - size.width - 8))
            origin.y = max(screen.visibleFrame.minY + 8, min(origin.y, screen.visibleFrame.maxY - size.height - 8))
        }
        panel.setFrameOrigin(origin)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

/// NSPanel that can become key even though the app is an accessory.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PickerView: View {
    let url: URL
    let choices: [PickerPanelController.Choice]
    let onPick: (PickerPanelController.Choice) -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onCreateRule: () -> Void

    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.controlSpacing) {
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            VStack(spacing: 2) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    let selected = index == selection
                    Button {
                        onPick(choice)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: choice.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(choice.title).lineLimit(1)
                            Spacer(minLength: 12)
                            if index < 9 {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
                                .fill(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { selection = index }
                    }
                }
            }

            Divider()

            HStack {
                Button("Create Rule for This Link…", action: onCreateRule)
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Text("esc fallback · ⌘C copy")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
        .padding(Metrics.panelPadding)
        .frame(width: 340)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelCornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .background(KeyCatcher(
            count: choices.count,
            selection: $selection,
            onPickIndex: { onPick(choices[$0]) },
            onCopy: onCopy,
            onCancel: onCancel
        ))
    }
}

/// Invisible NSView that owns first responder and translates key presses.
private struct KeyCatcher: NSViewRepresentable {
    let count: Int
    @Binding var selection: Int
    let onPickIndex: (Int) -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let v = KeyView()
        v.configure(self)
        return v
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.configure(self)
    }

    final class KeyView: NSView {
        private var parent: KeyCatcher?
        override var acceptsFirstResponder: Bool { true }

        func configure(_ parent: KeyCatcher) {
            self.parent = parent
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let parent else { return super.keyDown(with: event) }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                parent.onCopy()
                return
            }
            switch event.keyCode {
            case 53: // esc
                parent.onCancel()
            case 36, 76: // return / enter
                parent.onPickIndex(parent.selection)
            case 125: // down
                parent.selection = min(parent.selection + 1, parent.count - 1)
            case 126: // up
                parent.selection = max(parent.selection - 1, 0)
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let digit = Int(chars), digit >= 1, digit <= min(9, parent.count) {
                    parent.onPickIndex(digit - 1)
                } else {
                    super.keyDown(with: event)
                }
            }
        }
    }
}
#endif
