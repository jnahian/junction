#if canImport(AppKit)
import AppKit
import Foundation
import JunctionCore
import SwiftUI

/// Rules pane (F9): ordered list, drag-reorder, enable toggles, editor sheet.
struct RulesPane: View {
    @ObservedObject var state: AppState
    @State private var editingRule: Rule?
    @State private var isNewRule = false
    @State private var highlightedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(state.config.rules.enumerated()), id: \.element.id) { index, rule in
                    RuleRow(
                        rule: rule,
                        highlighted: index == highlightedIndex,
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
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if state.config.rules.isEmpty {
                    VStack(spacing: Metrics.controlSpacing) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No Rules").font(.title3.weight(.medium))
                        Text("Every link opens in your fallback browser until you add one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            // Standard source-list add/remove bar.
            HStack(spacing: 0) {
                Button {
                    isNewRule = true
                    editingRule = Rule(name: "New rule", match: Match(), action: .open(app: draftBrowser, profile: nil))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add a rule")

                Divider().frame(height: 16)

                Spacer()
                Text("First matching rule wins. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, Metrics.controlSpacing)
            }
            .padding(.horizontal, Metrics.controlSpacing)
            .padding(.vertical, 4)
            .background(.bar)
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
        .onReceive(NotificationCenter.default.publisher(for: .junctionPrefillRule)) { note in
            let url = note.userInfo?["url"] as? URL
            let sourceApp = note.userInfo?["sourceApp"] as? String
            var match = Match()
            if let url, let host = url.host {
                match.patterns = [host + "/*"]
            }
            if let sourceApp {
                match.sourceApps = [sourceApp]
            }
            isNewRule = true
            editingRule = Rule(
                name: url?.host.map { "Links on \($0)" } ?? "New rule",
                match: match,
                action: .open(app: draftBrowser, profile: nil)
            )
        }
    }

    /// Seed for a new rule's browser: the fallback when it's a real browser; the picker
    /// sentinel would make an unsendable draft, so leave the choice empty instead.
    private var draftBrowser: String {
        state.config.fallback.isPicker ? "" : state.config.fallback.app
    }

    private func actionLabel(_ action: Action) -> String {
        switch action {
        case .open(let app, let profile):
            let name = state.browsers.first(where: { $0.bundleID == app })?.name ?? app
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
    let highlighted: Bool
    let actionLabel: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.checkbox)
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
        .padding(.vertical, 2)
        .background(highlighted ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.2) : .clear)
        .opacity(rule.enabled ? 1 : 0.5)
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
