#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import JunctionMacKit
import SwiftUI

/// Editor sheet for a user-defined deep-link app (a custom rewriter), with a live preview
/// of what the entered URL rewrites to.
struct RewriterEditor: View {
    @ObservedObject var state: AppState
    /// nil when adding.
    let original: Rewriter?
    let onSave: (Rewriter) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var scheme: String
    @State private var patternsText: String
    @State private var template: String
    @State private var testURL = ""

    init(state: AppState, original: Rewriter?, onSave: @escaping (Rewriter) -> Void, onCancel: @escaping () -> Void) {
        self.state = state
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: original?.name ?? "")
        _scheme = State(initialValue: original?.scheme ?? "")
        _patternsText = State(initialValue: (original?.patterns ?? []).joined(separator: "\n"))
        _template = State(initialValue: original?.template ?? "")
    }

    private var patterns: [String] {
        patternsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var badPatterns: [String] {
        patterns.filter { (try? NSRegularExpression(pattern: $0)) == nil }
    }

    /// Stable across edits: renaming an existing app keeps its id, so `enabledRewriters`
    /// and any `deepLink` rule pointing at it don't break.
    private var id: String { original?.id ?? Self.slug(name) }

    private var built: Rewriter {
        Rewriter(id: id, name: name.trimmingCharacters(in: .whitespaces), patterns: patterns,
                 template: template.trimmingCharacters(in: .whitespaces),
                 scheme: scheme.trimmingCharacters(in: .whitespaces))
    }

    private var nameTaken: Bool {
        original == nil && state.config.customRewriters.contains { $0.id == id }
    }

    private var canSave: Bool {
        !id.isEmpty && !built.name.isEmpty && !built.scheme.isEmpty && !built.template.isEmpty
            && !patterns.isEmpty && badPatterns.isEmpty && !nameTaken
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if nameTaken {
                        Text("You already have an app named \(built.name).")
                            .font(.caption).foregroundStyle(.red)
                    }
                    TextField("URL scheme", text: $scheme, prompt: Text("e.g. linear"))
                        .font(.body.monospaced())
                    if !built.scheme.isEmpty, !BrowserDiscovery.isSchemeHandled(built.scheme) {
                        Text("No installed app handles \(built.scheme):// — links will fall back to the browser.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("The app")
                } footer: {
                    Text("The scheme is how macOS finds the app. It is the part before :// in a link the app itself can open.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $patternsText)
                        .font(.body.monospaced())
                        .frame(height: 70)
                    if let bad = badPatterns.first {
                        Text("Invalid regex: \(bad)").font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Web URL patterns (regex, one per line)")
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Matched against the whole URL. Round brackets capture text for the template.")
                        Text(verbatim: "e.g. ^https?://linear\\.app/(.*)$ captures everything after the host, so the template linear://$1 turns https://linear.app/acme/issue/ENG-1 into linear://acme/issue/ENG-1")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextField("Template", text: $template, prompt: Text("e.g. linear://$1"))
                        .font(.body.monospaced())
                } header: {
                    Text("App URL template")
                } footer: {
                    Text("$1…$9 insert the captures from the matching pattern.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Test") {
                    TextField("https://…", text: $testURL)
                    if let url = URL(string: testURL), !testURL.isEmpty {
                        if let out = built.rewrite(url, lookup: state.config.slackTeams) {
                            Text(out.absoluteString)
                                .font(.caption.monospaced()).foregroundStyle(.green)
                                .textSelection(.enabled)
                        } else {
                            Text("No pattern matches — this link would open in the browser.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave(built) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(Metrics.sectionSpacing)
            .background(.bar)
        }
        .frame(width: 520, height: 620)
    }

    /// "Linear Issues" → "linear-issues". Naming a custom app after a built-in shadows it.
    static func slug(_ s: String) -> String {
        let mapped = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }
}
#endif
