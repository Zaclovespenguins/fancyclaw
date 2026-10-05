import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

/// The pinned payload supplies independent policy/readiness/exposure facts, not a per-skill tool list.
struct SkillDetailView: View {
    @Environment(\.appTheme) private var theme
    let skill: SkillStatus
    let isStale: Bool

    var body: some View {
        List {
            Section {
                Text(skill.description).font(.callout)
                if isStale {
                    Label("Last loaded status · May have changed on the Gateway", systemImage: "clock")
                        .font(.footnote).foregroundStyle(theme.textSecondary.color)
                }
            }
            Section("Status") {
                LabeledContent("Availability", value: skill.availability.label)
                    .accessibilityIdentifier("skills.detail.status")
                fact("Disabled by configuration", skill.disabled)
                fact("Eligible on Gateway", skill.eligible)
                fact("Blocked by allowlist", skill.blockedByAllowlist)
                fact("Excluded from agent", skill.blockedByAgentFilter)
                fact("Platform incompatible", skill.platformIncompatible)
            }
            Section("Agent visibility") {
                fact("Visible in model prompt", skill.modelVisible)
                fact("Supports user invocation", skill.userInvocable)
                fact("Visible as user command", skill.commandVisible)
                Text("Model visibility and user commands are independent. A skill hidden from the model can still support user commands.")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
            }
            if let missing = skill.missing, !missing.isEmpty {
                Section("Missing requirements") {
                    requirements(missing)
                }
            }
            if let required = skill.requirements, !required.isEmpty {
                Section("Requirements") {
                    requirements(required)
                }
            }
            Section("Metadata") {
                LabeledContent("Configuration key", value: skill.skillKey)
                if let source = skill.source { LabeledContent("Source", value: source) }
                Text("Read-only. Skill changes are managed on your Gateway.")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
            }
            Section("Tools") {
                Text("The Gateway does not report which tools belong to this skill.")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { AmbientGlow() }
        .foregroundStyle(theme.textPrimary.color)
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("skills.detail")
    }

    private func fact(_ label: String, _ value: Bool?) -> some View {
        LabeledContent(label, value: value.map { $0 ? "Yes" : "No" } ?? "Not reported")
    }

    @ViewBuilder private func requirements(_ value: SkillRequirements) -> some View {
        requirement("Binaries", value.bins)
        // The set names alternatives; do not imply every member must be installed.
        requirement("At least one binary", value.anyBins)
        requirement("Environment variables", value.env)
        requirement("Configuration", value.config)
        requirement("Supported platforms", value.os)
    }

    @ViewBuilder private func requirement(_ label: String, _ values: [String]?) -> some View {
        if let values, !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline)
                Text(values.joined(separator: ", ")).font(.footnote.monospaced())
                    .foregroundStyle(theme.textSecondary.color)
                    .textSelection(.enabled)
            }
        }
    }
}
