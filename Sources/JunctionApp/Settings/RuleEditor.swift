#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import SwiftUI

/// Rule editor sheet with live pattern validation + example-match preview (PRD §10).
struct RuleEditor: View {
    @ObservedObject var state: AppState
    let original: Rule?
    let onSave: (Rule) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var notes: String
    @State private var patternsText: String
    @State private var regexText: String
    @State private var sourceApps: [String]
    @State private var actionKind: ActionKind
    @State private var actionApp: String
    @State private var actionProfile: String
    @State private var deepLinkID: String
    @State private var rewriteFind: String
    @State private var rewriteReplace: String
    @State private var testURL: String = ""

    enum ActionKind: String, CaseIterable, Identifiable {
        case open = "Open in browser"
        case deepLink = "Open native app (deep link)"
        case prompt = "Ask with picker"
        case clipboard = "Copy to clipboard"
        var id: String { rawValue }
    }

    init(state: AppState, original: Rule?, draft: Rule, onSave: @escaping (Rule) -> Void, onCancel: @escaping () -> Void) {
        self.state = state
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _notes = State(initialValue: draft.notes ?? "")
        _patternsText = State(initialValue: draft.match.patterns.joined(separator: "\n"))
        _regexText = State(initialValue: draft.match.regex ?? "")
        _sourceApps = State(initialValue: draft.match.sourceApps)
        _rewriteFind = State(initialValue: draft.rewrite?.find ?? "")
        _rewriteReplace = State(initialValue: draft.rewrite?.replace ?? "")
        switch draft.action {
        case .open(let app, let profile):
            _actionKind = State(initialValue: .open)
            _actionApp = State(initialValue: app)
            _actionProfile = State(initialValue: profile ?? "")
            _deepLinkID = State(initialValue: "")
        case .deepLink(let id):
            _actionKind = State(initialValue: .deepLink)
            _actionApp = State(initialValue: "")
            _actionProfile = State(initialValue: "")
            _deepLinkID = State(initialValue: id)
        case .prompt:
            _actionKind = State(initialValue: .prompt)
            _actionApp = State(initialValue: "")
            _actionProfile = State(initialValue: "")
            _deepLinkID = State(initialValue: "")
        case .clipboard:
            _actionKind = State(initialValue: .clipboard)
            _actionApp = State(initialValue: "")
            _actionProfile = State(initialValue: "")
            _deepLinkID = State(initialValue: "")
        }
    }

    private var patterns: [String] {
        patternsText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var invalidPatterns: [String] {
        patterns.filter { WildcardPattern($0) == nil }
    }

    private var regexValid: Bool {
        regexText.isEmpty || (try? NSRegularExpression(pattern: regexText)) != nil
    }

    private var builtRule: Rule {
        let match = Match(patterns: patterns, regex: regexText.isEmpty ? nil : regexText, sourceApps: sourceApps)
        let action: Action
        switch actionKind {
        case .open: action = .open(app: actionApp, profile: actionProfile.isEmpty ? nil : actionProfile)
        case .deepLink: action = .deepLink(deepLinkID)
        case .prompt: action = .prompt
        case .clipboard: action = .clipboard
        }
        // Preserve identity when editing so the save replaces in place.
        let rule = Rule(
            id: original?.id ?? UUID(),
            name: name.isEmpty ? "Untitled rule" : name,
            notes: notes.isEmpty ? nil : notes,
            enabled: original?.enabled ?? true,
            match: match,
            action: action,
            rewrite: rewriteFind.isEmpty ? nil : RegexRewrite(find: rewriteFind, replace: rewriteReplace)
        )
        return rule
    }

    private var canSave: Bool {
        guard invalidPatterns.isEmpty, regexValid else { return false }
        guard !builtRule.match.isEmpty else { return false }
        if actionKind == .open, actionApp.isEmpty { return false }
        if actionKind == .deepLink, deepLinkID.isEmpty { return false }
        return true
    }

    private var selectedBrowser: Browser? {
        state.browsers.first { $0.bundleID == actionApp }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Match — all groups must match; entries within a group are OR-ed") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL patterns (one per line, e.g. *.atlassian.net/*)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $patternsText)
                            .font(.body.monospaced())
                            .frame(height: 60)
                        if !invalidPatterns.isEmpty {
                            Label("Invalid: \(invalidPatterns.joined(separator: ", "))", systemImage: "xmark.circle")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    TextField("Regex over full URL (optional)", text: $regexText)
                        .font(.body.monospaced())
                    if !regexValid {
                        Label("Invalid regex", systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
                    }
                    SourceAppsField(sourceApps: $sourceApps)
                }
                Section("Action") {
                    Picker("Do", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    if actionKind == .open {
                        Picker("Browser", selection: $actionApp) {
                            Text("Choose…").tag("")
                            ForEach(state.browsers) { b in Text(b.name).tag(b.bundleID) }
                        }
                        if let browser = selectedBrowser, !browser.profiles.isEmpty {
                            Picker("Profile", selection: $actionProfile) {
                                Text("Default window").tag("")
                                ForEach(browser.profiles) { p in
                                    Text(p.displayName).tag(p.directory)
                                }
                            }
                        }
                    }
                    if actionKind == .deepLink {
                        Picker("App", selection: $deepLinkID) {
                            Text("Choose…").tag("")
                            ForEach(state.rewriters.rewriters) { r in Text(r.name).tag(r.id) }
                        }
                    }
                }
                Section("Rewrite (optional, runs before the action)") {
                    TextField("Find (regex)", text: $rewriteFind).font(.body.monospaced())
                    TextField("Replace", text: $rewriteReplace).font(.body.monospaced())
                }
                Section("Try it") {
                    TextField("Paste a URL to preview matching", text: $testURL)
                    if let url = URL(string: testURL), url.host != nil {
                        let compiled = CompiledPreview(rule: builtRule, url: url)
                        Label(
                            compiled.matches ? "This rule matches" : "No match",
                            systemImage: compiled.matches ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(compiled.matches ? .green : .secondary)
                        .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave(builtRule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 520, height: 620)
        .onAppear { state.refreshBrowsers() }
    }
}

/// Lightweight match preview using a single-rule engine.
private struct CompiledPreview {
    let matches: Bool
    init(rule: Rule, url: URL) {
        var rule = rule
        rule.enabled = true
        let config = Config(rules: [rule])
        let engine = RoutingEngine(config: config, rewriters: RewriterStore(rewriters: []))
        matches = engine.trace(LinkEvent(url: url, sourceApp: rule.match.sourceApps.first)).matchedRuleIndex == 0
    }
}

/// Source-app list editor: running/installed app picker + manual bundle-ID entry (F3).
struct SourceAppsField: View {
    @Binding var sourceApps: [String]
    @State private var manualEntry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source apps (bundle IDs — rule fires only for links clicked in these apps)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(sourceApps, id: \.self) { app in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 16, height: 16)
                    }
                    Text(app).font(.caption.monospaced())
                    Spacer()
                    Button {
                        sourceApps.removeAll { $0 == app }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                }
            }
            HStack {
                Menu("Add App") {
                    ForEach(runningApps(), id: \.0) { bundleID, name in
                        Button(name) {
                            if !sourceApps.contains(bundleID) { sourceApps.append(bundleID) }
                        }
                    }
                }
                .frame(width: 120)
                TextField("or type a bundle ID", text: $manualEntry, onCommit: {
                    let trimmed = manualEntry.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !sourceApps.contains(trimmed) {
                        sourceApps.append(trimmed)
                    }
                    manualEntry = ""
                })
                .font(.caption.monospaced())
            }
        }
    }

    private func runningApps() -> [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}
#endif
