#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import SwiftUI

/// Rules pane (F9): ordered list, drag-reorder, enable switches, editor sheet.
struct RulesPane: View {
    @ObservedObject var state: AppState
    @ObservedObject var nav: SettingsNavigation
    @State private var editingRule: Rule?
    @State private var isNewRule = false

    var body: some View {
        List {
            ForEach(Array(state.config.rules.enumerated()), id: \.element.id) { index, rule in
                RuleRow(
                    rule: rule,
                    actionLabel: actionLabel(rule.action),
                    onToggle: { enabled in
                        state.updateConfig { $0.rules[index].enabled = enabled }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    isNewRule = false
                    editingRule = rule
                }
                .contextMenu {
                    Button("Edit…") { isNewRule = false; editingRule = rule }
                    Button("Duplicate") {
                        let copy = Rule(name: rule.name + " copy", notes: rule.notes, enabled: rule.enabled,
                                        match: rule.match, action: rule.action, rewrite: rule.rewrite)
                        state.updateConfig { $0.rules.insert(copy, at: index + 1) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        state.updateConfig { $0.rules.remove(at: index) }
                    }
                }
            }
            .onMove { source, destination in
                state.updateConfig { $0.rules.move(fromOffsets: source, toOffset: destination) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if state.config.rules.isEmpty {
                VStack(spacing: Metrics.controlSpacing) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No Rules").font(.title3.weight(.medium))
                    Text("Every link goes to your fallback until you add one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(
                state: state,
                original: isNewRule ? nil : rule,
                draft: rule
            ) { saved in
                state.updateConfig { config in
                    if isNewRule {
                        config.rules.append(saved)
                    } else if let i = config.rules.firstIndex(where: { $0.id == rule.id }) {
                        config.rules[i] = saved
                    }
                }
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
        .onAppear(perform: takeNewRuleRequest)
        .onChange(of: nav.newRule?.id) { _ in takeNewRuleRequest() }
    }

    /// Opens the editor on a new rule, seeded from the link when there is one.
    private func takeNewRuleRequest() {
        guard let request = nav.newRule else { return }
        nav.newRule = nil
        var match = Match()
        if let host = request.url?.host {
            match.patterns = [host + "/*"]
        }
        if let sourceApp = request.sourceApp {
            match.sourceApps = [sourceApp]
        }
        isNewRule = true
        editingRule = Rule(
            name: request.url?.host.map { "Links on \($0)" } ?? "New rule",
            match: match,
            action: .open(app: draftBrowser, profile: nil)
        )
    }

    /// Seed for a new rule's browser: the fallback when it's a real browser; the picker
    /// sentinel would make an unsendable draft, so leave the choice empty instead.
    private var draftBrowser: String {
        state.config.fallback.isPicker ? "" : state.config.fallback.app
    }

    private func actionLabel(_ action: Action) -> String {
        switch action {
        case .open(let app, let profile):
            let name = state.browsers.first(where: { $0.bundleID == app })?.name
                ?? state.webApps.first(where: { $0.bundleID == app })?.name ?? app
            return profile.map { "\(name) · \($0)" } ?? name
        case .deepLink(let id):
            return "Deep link: \(state.rewriters.rewriter(id: id)?.name ?? id)"
        case .prompt: return "Ask (picker)"
        case .clipboard: return "Copy to clipboard"
        }
    }
}

private struct RuleRow: View {
    let rule: Rule
    let actionLabel: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            // Dim what a turned-off rule says, not its switch, which would look disabled.
            Group {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                    Text(matchSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(actionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(rule.enabled ? 1 : 0.5)
        }
        .padding(.vertical, 2)
    }

    private var matchSummary: String {
        var parts: [String] = []
        if !rule.match.patterns.isEmpty { parts.append(rule.match.patterns.joined(separator: ", ")) }
        if let r = rule.match.regex { parts.append("regex: \(r)") }
        if !rule.match.sourceApps.isEmpty { parts.append("from " + rule.match.sourceApps.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
#endif
