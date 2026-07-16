#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import ServiceManagement
import Sparkle
import SwiftUI

// MARK: - Browsers (F9)

struct BrowsersPane: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Fallback (used when no rule matches)") {
                Picker("Fallback", selection: Binding(
                    get: { state.config.fallback.app },
                    set: { id in state.updateConfig { $0.fallback.app = id } }
                )) {
                    Text("Ask every time (show the picker)").tag(Fallback.picker)
                    Divider()
                    ForEach(state.browsers) { b in Text(b.name).tag(b.bundleID) }
                    if state.config.fallback.app != Fallback.picker,
                       !state.browsers.contains(where: { $0.bundleID == state.config.fallback.app }) {
                        Text(state.config.fallback.app).tag(state.config.fallback.app)
                    }
                }
            }
            Section {
                ForEach(state.browsers) { browser in
                    Toggle(isOn: pickerVisibility(browser.bundleID)) {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.appURL.path))
                                .resizable().frame(width: 18, height: 18)
                            Text(browser.name)
                            Text(browser.bundleID).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(browser.profiles) { profile in
                        Toggle(isOn: pickerVisibility("\(browser.bundleID)/\(profile.directory)")) {
                            // Firefox has no label distinct from its profile name, so
                            // don't render "default (default)".
                            Text(profile.displayName == profile.directory
                                ? profile.displayName
                                : "\(profile.displayName) (\(profile.directory))")
                                .font(.callout)
                                .padding(.leading, 26)
                        }
                    }
                }
                Button("Refresh") { state.refreshBrowsers() }
            } header: {
                Text("Detected browsers & profiles")
            } footer: {
                Text("Checked entries appear in the picker. Hidden ones can still be a rule target or the fallback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Chromium and Firefox profiles are detected automatically. Firefox containers are an extension feature with no launch-flag equivalent, so they are unsupported, as are Arc spaces (no public API).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshBrowsers() }
    }

    /// Shown-in-picker toggle backed by `config.pickerHidden` (stored inverted).
    private func pickerVisibility(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !state.config.pickerHidden.contains(key) },
            set: { shown in
                state.updateConfig { config in
                    if shown {
                        config.pickerHidden.removeAll { $0 == key }
                    } else if !config.pickerHidden.contains(key) {
                        config.pickerHidden.append(key)
                    }
                }
            }
        )
    }
}

// MARK: - Deep Links (F4 toggles)

struct DeepLinksPane: View {
    @ObservedObject var state: AppState
    @State private var newSubdomain = ""
    @State private var newTeamID = ""
    @State private var editing: RewriterEditing?

    /// One sheet, not two: a blank draft's id is "" (slug of an empty name), so
    /// `.sheet(item:)` on a Rewriter wouldn't re-fire for a second "Add".
    enum RewriterEditing: Identifiable {
        case add
        case edit(Rewriter)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let r): return "edit-\(r.id)"
            }
        }
    }

    /// Custom rewriters shadow built-ins by id, so list them once, in their own section.
    private var builtins: [Rewriter] {
        let custom = Set(state.config.customRewriters.map(\.id))
        return state.rewriters.rewriters.filter { !custom.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(builtins) { rewriter in
                    rewriterToggle(rewriter)
                }
            } header: {
                Text("Open links in native apps instead of the browser")
            } footer: {
                Text("Built-ins are all off until you switch them on. A rewriter only fires when its app is installed and no rule matched first. Rules with a deep-link action always work regardless of these switches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            customRewritersSection
            slackTeamsSection
            Section {
                Text("Built-in definitions live in rewriters.json. Contributions welcome, no Swift required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { item in
            let original: Rewriter? = { if case .edit(let r) = item { return r } else { return nil } }()
            RewriterEditor(
                state: state,
                original: original,
                onSave: { saveRewriter($0, original: original) },
                onCancel: { editing = nil }
            )
        }
    }

    private func rewriterToggle(_ rewriter: Rewriter) -> some View {
        Toggle(isOn: Binding(
            get: { state.config.enabledRewriters.contains(rewriter.id) },
            set: { on in
                state.updateConfig { config in
                    if on {
                        if !config.enabledRewriters.contains(rewriter.id) {
                            config.enabledRewriters.append(rewriter.id)
                        }
                    } else {
                        config.enabledRewriters.removeAll { $0 == rewriter.id }
                    }
                }
            }
        )) {
            HStack {
                Text(rewriter.name)
                if !BrowserDiscovery.isSchemeHandled(rewriter.scheme) {
                    Text("app not installed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var customRewritersSection: some View {
        Section {
            ForEach(state.config.customRewriters) { rewriter in
                rewriterToggle(rewriter)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = .edit(rewriter) }
                    .contextMenu {
                        Button("Edit…") { editing = .edit(rewriter) }
                        Divider()
                        // Deleting an app a rule deep-links to would leave that rule pointing at
                        // nothing (config.validate rejects it), so send the user to fix the rule.
                        let users = rulesDeepLinking(to: rewriter.id)
                        Button(users.isEmpty ? "Delete" : "Used by \(users.joined(separator: ", "))",
                               role: .destructive) {
                            state.updateConfig { config in
                                config.customRewriters.removeAll { $0.id == rewriter.id }
                                config.enabledRewriters.removeAll { $0 == rewriter.id }
                            }
                        }
                        .disabled(!users.isEmpty)
                    }
            }
            Button("Add App…") { editing = .add }
        } header: {
            Text("Your apps")
        } footer: {
            Text("Teach Junction any app with a URL scheme. An app you add is on straight away. Double-click to edit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rulesDeepLinking(to id: String) -> [String] {
        state.config.rules.compactMap { rule in
            if case .deepLink(let target) = rule.action, target == id { return rule.name }
            return nil
        }
    }

    private func saveRewriter(_ rewriter: Rewriter, original: Rewriter?) {
        state.updateConfig { config in
            if let original, let i = config.customRewriters.firstIndex(where: { $0.id == original.id }) {
                config.customRewriters[i] = rewriter
            } else {
                config.customRewriters.append(rewriter)
                if !config.enabledRewriters.contains(rewriter.id) {
                    config.enabledRewriters.append(rewriter.id)
                }
            }
        }
        editing = nil
    }

    /// Slack's scheme takes team IDs, never subdomains, and a permalink carries only the
    /// subdomain — so Slack links can't deep-link until the user maps their workspaces.
    private var slackTeamsSection: some View {
        Section {
            ForEach(state.config.slackTeams.keys.sorted(), id: \.self) { subdomain in
                HStack {
                    Text("\(subdomain).slack.com")
                    Spacer()
                    Text(state.config.slackTeams[subdomain] ?? "").font(.callout.monospaced())
                    Button {
                        state.updateConfig { $0.slackTeams[subdomain] = nil }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(subdomain)")
                }
            }
            HStack {
                TextField("workspace", text: $newSubdomain)
                TextField("T01ABCDEF", text: $newTeamID)
                Button("Add") {
                    let subdomain = newSubdomain.trimmingCharacters(in: .whitespaces).lowercased()
                    let team = newTeamID.trimmingCharacters(in: .whitespaces).uppercased()
                    guard !subdomain.isEmpty, !team.isEmpty else { return }
                    state.updateConfig { $0.slackTeams[subdomain] = team }
                    newSubdomain = ""
                    newTeamID = ""
                }
            }
        } header: {
            Text("Slack workspaces")
        } footer: {
            Text("Slack's deep links need the team ID, which its permalinks don't carry. Open Slack in a browser: the URL reads app.slack.com/client/TEAM_ID/… — that's the ID. Unmapped workspaces open in the browser instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Transforms (F6)

struct TransformsPane: View {
    @ObservedObject var state: AppState
    @State private var newParam = ""

    var body: some View {
        Form {
            Section {
                Toggle("Strip tracking parameters (utm_*, fbclid, gclid, …)", isOn: Binding(
                    get: { state.config.stripTrackingParams },
                    set: { on in state.updateConfig { $0.stripTrackingParams = on } }
                ))
            }
            Section("Extra parameters to strip (suffix * for prefix match)") {
                ForEach(state.config.extraTrackingParams, id: \.self) { param in
                    HStack {
                        Text(param).font(.body.monospaced())
                        Spacer()
                        Button {
                            state.updateConfig { $0.extraTrackingParams.removeAll { $0 == param } }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("e.g. ref or mycorp_*", text: $newParam)
                        .font(.body.monospaced())
                    Button("Add") {
                        let trimmed = newParam.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        state.updateConfig { config in
                            if !config.extraTrackingParams.contains(trimmed) {
                                config.extraTrackingParams.append(trimmed)
                            }
                        }
                        newParam = ""
                    }
                }
            }
            Section {
                Text("Per-rule regex rewrites are edited inside each rule.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tester (F8)

struct TesterPane: View {
    @ObservedObject var state: AppState
    @State private var urlText = ""
    @State private var simulatedSource = ""

    var body: some View {
        Form {
            Section("Simulate a link click") {
                TextField("URL", text: $urlText, prompt: Text("https://mycorp.atlassian.net/browse/X-1"))
                    .font(.body.monospaced())
                TextField("Simulated source app (bundle ID, optional)", text: $simulatedSource)
                    .font(.body.monospaced())
            }
            if let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)), url.host != nil {
                let trace = state.engine.trace(LinkEvent(
                    url: url,
                    sourceApp: simulatedSource.isEmpty ? nil : simulatedSource
                ))
                Section("Result") {
                    LabeledContent("After transforms", value: trace.transformedURL.absoluteString)
                    LabeledContent("Matched rule", value: trace.matchedRule ?? (trace.rewriterID.map { "built-in rewriter: \($0)" } ?? "none (fallback)"))
                    LabeledContent("Decision", value: describe(trace.decision))
                    LabeledContent("Final URL", value: trace.decision.url.absoluteString)
                }
            } else if !urlText.isEmpty {
                Section { Text("Not a valid URL yet…").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func describe(_ d: RoutingDecision) -> String {
        switch d {
        case .open(let app, let profile, _):
            return "Open in \(app)" + (profile.map { " · profile \($0)" } ?? "")
        case .deepLink(let url, let id, _):
            return "Deep link via \(id) → \(url.scheme ?? "?")://"
        case .prompt: return "Show picker"
        case .clipboard: return "Copy to clipboard"
        case .fallback(let app, _): return "Fallback → \(app)"
        }
    }
}

// MARK: - General (F9)

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/jnahian/junction")!
    static let issuesURL = URL(string: "https://github.com/jnahian/junction/issues/new")!
    static let authorURL = URL(string: "https://github.com/jnahian")!

    /// Only the packaged app has a version; `swift run` has no Info.plist.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

struct GeneralPane: View {
    @ObservedObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Default browser") {
                if state.isDefaultBrowser {
                    Label("Junction is your default browser", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Junction is not your default browser, so links won't be routed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Set as Default Browser…") { state.requestDefaultBrowser() }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Config file") {
                LabeledContent("Path", value: state.configStore.fileURL.path)
                    .font(.caption.monospaced())
                HStack {
                    Button("Open Config File") {
                        NSWorkspace.shared.open(state.configStore.fileURL)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([state.configStore.fileURL])
                    }
                }
                if let error = state.configError {
                    Text(error.description).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Onboarding") {
                Button("Show Welcome Tour…") {
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")
                    state.onboardingPresenter?()
                }
                Text("Re-runs the first-launch flow. Picking a fallback or starter rules again updates your existing config.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                LabeledContent("Version", value: AppInfo.versionString)
                if updaterController != nil {
                    Button("Check for Updates…") {
                        NSApp.activate(ignoringOtherApps: true)
                        updaterController?.checkForUpdates(nil)
                    }
                } else {
                    // No SUFeedURL under `swift run`; the packaged app always has one.
                    Button("View Releases on GitHub…") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/jnahian/junction/releases")!)
                    }
                }
                Text("Junction checks GitHub for new versions and makes no other network calls. Zero telemetry: the links you open never leave your Mac or touch disk.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshDefaultBrowserStatus() }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Junction").font(.largeTitle.bold())
                Text("Version \(AppInfo.versionString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Every link, in the right place. Junction is your default browser, routing each link to the right browser, profile, or native app — with no telemetry.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text("Made by Julkar Naen Nahian")
                .font(.callout)
            HStack(spacing: Metrics.controlSpacing) {
                Link("Report an Issue", destination: AppInfo.issuesURL)
                Link("Source Code", destination: AppInfo.repoURL)
                Link("Author", destination: AppInfo.authorURL)
            }
            .buttonStyle(.link)
            Spacer()
            Text("MIT licensed").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(Metrics.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
