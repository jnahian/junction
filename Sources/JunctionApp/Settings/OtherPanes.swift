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
            Section("Fallback browser (used when no rule matches)") {
                Picker("Fallback", selection: Binding(
                    get: { state.config.fallback.app },
                    set: { id in state.updateConfig { $0.fallback.app = id } }
                )) {
                    ForEach(state.browsers) { b in Text(b.name).tag(b.bundleID) }
                    if !state.browsers.contains(where: { $0.bundleID == state.config.fallback.app }) {
                        Text(state.config.fallback.app).tag(state.config.fallback.app)
                    }
                }
            }
            Section("Detected browsers & profiles") {
                ForEach(state.browsers) { browser in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.appURL.path))
                                .resizable().frame(width: 18, height: 18)
                            Text(browser.name)
                            Text(browser.bundleID).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                        if !browser.profiles.isEmpty {
                            Text("Profiles: " + browser.profiles.map {
                                // Firefox has no label distinct from its profile name, so
                                // don't render "default (default)".
                                $0.displayName == $0.directory
                                    ? $0.displayName
                                    : "\($0.displayName) (\($0.directory))"
                            }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 26)
                        }
                    }
                }
                Button("Refresh") { state.refreshBrowsers() }
            }
            Section {
                Text("Chromium and Firefox profiles are detected automatically. Firefox containers are an extension feature with no launch-flag equivalent, so they are unsupported, as are Arc spaces (no public API).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshBrowsers() }
    }
}

// MARK: - Deep Links (F4 toggles)

struct DeepLinksPane: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(state.rewriters.rewriters) { rewriter in
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
            } header: {
                Text("Open links in native apps instead of the browser")
            } footer: {
                Text("All off by default. A rewriter only fires when its app is installed and no rule matched first. Rules with a deep-link action always work regardless of these switches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Definitions live in rewriters.json. Contributions welcome, no Swift required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
#endif
