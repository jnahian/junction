#if canImport(AppKit)
import AppKit
import Combine
import Foundation
import JunctionMacKit
import SwiftUI

/// Floating, keyboard-first browser picker (F7): appears at the cursor,
/// `1–9` open, arrows+Return navigate, `Esc` = close, `⌘C` = copy.
@MainActor
final class PickerPanelController: NSObject, NSWindowDelegate {
    /// The links currently represented by the visible picker. A session survives
    /// additional open events so the panel does not race itself away.
    @MainActor
    final class Session: ObservableObject, Identifiable {
        let id: UUID
        @Published private(set) var urls: [URL]

        init(id: UUID = UUID(), urls: [URL]) {
            self.id = id
            self.urls = urls
        }

        func append(_ newURLs: [URL]) {
            urls.append(contentsOf: newURLs)
        }
    }

    private let state: AppState?
    private let choicesProvider: () -> [Choice]
    private let openEffect: ([URL], Choice, @escaping @MainActor (BrowserBatchOutcome) -> Void) -> Void
    private let copyEffect: (String) -> Void
    private let copiedConfirmation: (Int) -> Void
    private let noChoicesEffect: ([URL]) -> Void
    private let createRuleEffect: (URL) -> Void
    private let presentsPanel: Bool
    private let injectedPresentation: ((Session, [Choice]) -> Void)?
    private let visibleFrameProvider: (NSPoint) -> NSRect?
    private(set) var panel: NSPanel?
    private(set) var session: Session?
    private var hasBecomeKey = false
    private var finishingSessionID: UUID?
    private var pendingURLs: [URL] = []

    init(state: AppState) {
        self.state = state
        self.choicesProvider = { [weak state] in
            guard let state else { return [] }
            state.refreshBrowsers()

            // Rows the user hid in Settings → Browsers (key: bundleID or bundleID/profileDir).
            // If hiding emptied the whole list, ignore the hidden set — an unusable picker is worse.
            let hidden = Set(state.config.pickerHidden)
            var choices = Self.buildChoices(from: state.browsers, skipping: hidden)
            if choices.isEmpty { choices = Self.buildChoices(from: state.browsers, skipping: []) }
            return choices
        }
        self.openEffect = { [weak state] urls, choice, completion in
            guard let state else { completion(.needsPicker); return }
            state.open(urls: urls, in: choice.browser, profile: choice.profile, completion: completion)
        }
        self.copyEffect = { links in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(links, forType: .string)
        }
        self.copiedConfirmation = { [weak state] count in state?.showCopiedConfirmation(count: count) }
        self.noChoicesEffect = { [weak state] urls in
            guard let state else { return }
            // No browsers detected at all. With a browser fallback, degrade there; with the
            // picker fallback there is nothing to open (recursing here would loop), so keep
            // the whole batch on the clipboard instead of dropping it.
            if state.config.fallback.isPicker {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
                state.showCopiedConfirmation(count: urls.count)
            } else {
                for url in urls { state.openInFallback(url) }
            }
        }
        self.createRuleEffect = { [weak state] url in
            state?.settingsPresenter?()
            NotificationCenter.default.post(
                name: .junctionPrefillRule, object: nil,
                userInfo: ["url": url]
            )
        }
        self.presentsPanel = true
        self.injectedPresentation = nil
        self.visibleFrameProvider = Self.visibleFrame
        super.init()
    }

    /// Dependency seams keep the session and action behavior testable without launching a
    /// browser, touching the clipboard, or loading the user's config file.
    init(
        choices: @escaping () -> [Choice],
        open: @escaping ([URL], Choice, @escaping @MainActor (BrowserBatchOutcome) -> Void) -> Void,
        copy: @escaping (String) -> Void,
        copiedConfirmation: @escaping (Int) -> Void = { _ in },
        noChoices: @escaping ([URL]) -> Void = { _ in },
        createRule: @escaping (URL) -> Void = { _ in },
        presentsPanel: Bool = false,
        presentSession: ((Session, [Choice]) -> Void)? = nil,
        visibleFrame: ((NSPoint) -> NSRect?)? = nil
    ) {
        self.state = nil
        self.choicesProvider = choices
        self.openEffect = open
        self.copyEffect = copy
        self.copiedConfirmation = copiedConfirmation
        self.noChoicesEffect = noChoices
        self.createRuleEffect = createRule
        self.presentsPanel = presentsPanel
        self.injectedPresentation = presentSession
        self.visibleFrameProvider = visibleFrame ?? Self.visibleFrame
        super.init()
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
        if finishingSessionID != nil {
            // Retry requests must stay together until the current batch has finished.
            // In particular, an empty browser list must copy the whole retry batch once.
            pendingURLs.append(url)
            return
        }
        show(urls: [url])
    }

    private func show(urls: [URL]) {
        if let session {
            session.append(urls)
            resizePanel(for: session.id)
            return
        }

        let choices = choicesProvider()
        guard !choices.isEmpty else {
            noChoicesEffect(urls)
            return
        }

        let session = Session(urls: urls)
        self.session = session
        if presentsPanel { present(session: session, choices: choices) }
    }

    private func present(session: Session, choices: [Choice]) {
        guard self.session?.id == session.id, panel == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screenFrame = visibleFrameProvider(mouse)
        let view = PickerView(
            session: session,
            maximumHeight: screenFrame.map { max(0, $0.height - 16) } ?? 800,
            choices: choices,
            onPick: { [weak self, weak session] choice in
                guard let session else { return }
                self?.pick(choice, sessionID: session.id)
            },
            onCopy: { [weak self, weak session] in
                guard let session else { return }
                self?.copy(sessionID: session.id)
            },
            // Esc abandons the link on purpose — closing without opening anything is
            // the user's choice, not a lost link.
            onCancel: { [weak self, weak session] in
                guard let session else { return }
                self?.cancel(sessionID: session.id)
            },
            onCreateRule: { [weak self, weak session] in
                guard let session else { return }
                self?.createRule(sessionID: session.id)
            },
            onContentSizeChange: { [weak self, weak session] in
                guard let session else { return }
                self?.resizePanel(for: session.id)
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
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        panel.setContentSize(hosting.view.fittingSize)

        // Appear at the cursor, keeping every edge within the usable screen.
        let size = panel.frame.size
        let origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 8)
        let frame = screenFrame.map { Self.constrainedFrame(size: size, origin: origin, visibleFrame: $0) }
            ?? NSRect(origin: origin, size: size)
        panel.setFrame(frame, display: false)

        self.panel = panel
        hasBecomeKey = false
        if let injectedPresentation {
            // A presentation hook can inspect the real hosted panel without activating it.
            injectedPresentation(session, choices)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func buildChoices(from browsers: [Browser], skipping hidden: Set<String>) -> [Choice] {
        var choices: [Choice] = []
        for browser in browsers {
            if !hidden.contains(browser.bundleID) {
                choices.append(Choice(browser: browser, profile: nil))
            }
            for profile in browser.profiles
            where !hidden.contains("\(browser.bundleID)/\(profile.directory)") {
                choices.append(Choice(browser: browser, profile: profile))
            }
        }
        return choices
    }

    func dismiss() {
        guard let session else {
            panel?.delegate = nil
            panel?.close()
            panel = nil
            hasBecomeKey = false
            return
        }
        cancel(sessionID: session.id)
    }

    private func closePanel(for sessionID: UUID) {
        guard let session, session.id == sessionID else { return }
        let panel = self.panel

        // Clear both first: closing the key window resigns key, which calls back in here.
        self.session = nil
        self.panel = nil
        hasBecomeKey = false
        panel?.delegate = nil
        panel?.close()
    }

    func cancel(sessionID: UUID) {
        guard session?.id == sessionID else { return }
        closePanel(for: sessionID)
    }

    func pick(_ choice: Choice, sessionID: UUID) {
        guard finishingSessionID == nil,
              let session,
              session.id == sessionID else { return }

        let urls = session.urls
        finishingSessionID = sessionID
        closePanel(for: sessionID)
        // Resolve and open the batch once. A successful first launch must not steal focus
        // from a retry panel created for a later URL in the same batch.
        openEffect(urls, choice) { [weak self] outcome in
            self?.finishOpening(sessionID: sessionID, urls: urls, outcome: outcome)
        }
    }

    private func finishOpening(sessionID: UUID, urls: [URL], outcome: BrowserBatchOutcome) {
        guard finishingSessionID == sessionID else { return }
        finishingSessionID = nil
        let remaining: [URL]
        switch outcome {
        case .needsPicker, .failed:
            remaining = urls + pendingURLs
        case .opened, .degradedToFallback:
            remaining = pendingURLs
        }
        pendingURLs.removeAll()
        if !remaining.isEmpty { show(urls: remaining) }
    }

    func copy(sessionID: UUID) {
        guard finishingSessionID == nil,
              let session,
              session.id == sessionID else { return }

        let urls = session.urls
        closePanel(for: sessionID)
        copyEffect(urls.map(\.absoluteString).joined(separator: "\n"))
        copiedConfirmation(urls.count)
    }

    func createRule(sessionID: UUID) {
        guard finishingSessionID == nil,
              let session,
              session.id == sessionID,
              session.urls.count == 1,
              let url = session.urls.first else { return }

        closePanel(for: sessionID)
        createRuleEffect(url)
    }

    private func resizePanel(for sessionID: UUID) {
        guard session?.id == sessionID, let panel else { return }
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self,
                  self.session?.id == sessionID,
                  let panel,
                  panel === self.panel,
                  let hosting = panel.contentViewController as? NSHostingController<PickerView> else {
                return
            }

            let oldFrame = panel.frame
            let center = NSPoint(x: oldFrame.midX, y: oldFrame.midY)
            let screenFrame = self.visibleFrameProvider(center) ?? panel.screen?.visibleFrame
            if let screenFrame { hosting.rootView.maximumHeight = max(0, screenFrame.height - 16) }
            hosting.view.layoutSubtreeIfNeeded()
            let fittingSize = hosting.view.fittingSize
            guard fittingSize.width > 0, fittingSize.height > 0 else { return }
            let origin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - fittingSize.height)
            let frame = screenFrame.map {
                Self.constrainedFrame(size: fittingSize, origin: origin, visibleFrame: $0)
            } ?? NSRect(origin: origin, size: fittingSize)
            panel.setFrame(frame, display: true)
        }
    }

    private static func visibleFrame(at point: NSPoint) -> NSRect? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }?.visibleFrame
    }

    static func constrainedFrame(size: NSSize, origin: NSPoint, visibleFrame: NSRect) -> NSRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = NSSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        return NSRect(
            x: max(bounds.minX, min(origin.x, bounds.maxX - size.width)),
            y: max(bounds.minY, min(origin.y, bounds.maxY - size.height)),
            width: size.width,
            height: size.height
        )
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let activePanel = panel,
              let notifiedPanel = notification.object as? NSWindow,
              notifiedPanel === activePanel else { return }
        hasBecomeKey = true
    }

    /// Clicking away abandons the link the same way Esc does — close, open nothing.
    /// Only once the panel has actually been key: showing it activates the app, and a
    /// resign in that churn would dismiss the picker before anyone saw it, losing the link.
    func windowDidResignKey(_ notification: Notification) {
        guard let activePanel = panel,
              let notifiedPanel = notification.object as? NSWindow,
              notifiedPanel === activePanel,
              hasBecomeKey else { return }
        dismiss()
    }

    /// Test seam for the delegate's identity and focus gate. Production panels are installed
    /// by show(for:) and always use the same identity check above.
    func installPanelForTesting(_ panel: NSPanel) {
        self.panel = panel
        panel.delegate = self
        hasBecomeKey = false
    }
}

/// NSPanel that can become key even though the app is an accessory.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PickerView: View {
    @ObservedObject var session: PickerPanelController.Session
    var maximumHeight: CGFloat
    let choices: [PickerPanelController.Choice]
    let onPick: (PickerPanelController.Choice) -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onCreateRule: () -> Void
    let onContentSizeChange: () -> Void

    @State private var selection = 0
    @State private var keyboardScrollTarget: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.controlSpacing) {
            if session.urls.count == 1, let url = session.urls.first {
                Text(url.absoluteString)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            } else {
                Text("\(session.urls.count) Links")
                    .font(.headline)
                    .padding(.horizontal, 6)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(session.urls.enumerated()), id: \.offset) { _, url in
                            Text(url.absoluteString)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(120, CGFloat(session.urls.count) * 17 - 4))
                .layoutPriority(1)
            }

            ScrollViewReader { proxy in
                ScrollView {
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
                            .id(index)
                            .onHover { hovering in
                                if hovering { selection = index }
                            }
                        }
                    }
                }
                .frame(idealHeight: CGFloat(choices.count) * 34 - 2, maxHeight: CGFloat(choices.count) * 34 - 2)
                .onChange(of: keyboardScrollTarget) { target in
                    if let target { proxy.scrollTo(target, anchor: .center) }
                }
                .onChange(of: session.urls.count) { _ in
                    DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
                }
            }

            Divider()

            HStack {
                Button("Create Rule for This Link…", action: onCreateRule)
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(session.urls.count != 1)
                    .help(session.urls.count == 1
                        ? "Create a rule for this link"
                        : "Create Rule is available for one link at a time")
                Button(session.urls.count == 1 ? "Copy Link" : "Copy \(session.urls.count) Links", action: onCopy)
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Text("esc close · ⌘C copy")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .padding(Metrics.panelPadding)
        .frame(width: 340)
        .frame(maxHeight: maximumHeight)
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
            onMoveSelection: { keyboardScrollTarget = $0 },
            onCopy: onCopy,
            onCancel: onCancel
        ))
        .onChange(of: session.urls.count) { _ in
            onContentSizeChange()
        }
    }
}

/// Invisible NSView that owns first responder and translates key presses.
private struct KeyCatcher: NSViewRepresentable {
    let count: Int
    @Binding var selection: Int
    let onPickIndex: (Int) -> Void
    let onMoveSelection: (Int) -> Void
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
                parent.onMoveSelection(parent.selection)
            case 126: // up
                parent.selection = max(parent.selection - 1, 0)
                parent.onMoveSelection(parent.selection)
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
