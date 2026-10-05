import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct SkillsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var store: SkillStore
    let isConnected: Bool
    let onReconnect: () async -> Void
    @State private var selectedSkill: SkillStatus?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Installed on your Gateway · Read-only")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
                if !isConnected || store.isStale {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(store.hasLoaded ? (isConnected ? "Showing the last loaded skills" : "Offline · Showing the last loaded skills") : "Offline · Connect to load skills",
                              systemImage: "wifi.slash")
                            .font(.subheadline).foregroundStyle(theme.textSecondary.color)
                        if !isConnected {
                            Button("Reconnect") { Task { await onReconnect() } }
                                .frame(minHeight: 44).accessibilityIdentifier("skills.reconnect")
                        }
                    }
                }
                if let error = store.errorMessage {
                    ErrorBanner(message: error) { store.errorMessage = nil }
                    Button("Retry") { Task { await store.refresh() } }
                        .frame(minHeight: 44).disabled(!isConnected || store.isLoading)
                        .accessibilityIdentifier("skills.retry")
                }
                if store.isLoading {
                    ProgressView("Loading skills…").frame(maxWidth: .infinity)
                        .accessibilityIdentifier("skills.loading")
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.visibleSkills) { skill in
                        Button { selectedSkill = skill } label: { SkillTile(skill: skill) }
                            .buttonStyle(PressScale())
                            .accessibilityIdentifier("skills.tile.\(skill.id)")
                    }
                }
                if store.visibleSkills.isEmpty && !store.isLoading && store.errorMessage == nil {
                    if !store.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: store.search)
                            .accessibilityIdentifier("skills.searchEmpty")
                    } else if isConnected && store.hasLoaded {
                        ContentUnavailableView("No skills installed", systemImage: "square.grid.2x2",
                            description: Text("Installed skills from your Gateway will appear here."))
                            .accessibilityIdentifier("skills.empty")
                    } else if !isConnected {
                        ContentUnavailableView("Skills unavailable offline", systemImage: "wifi.slash",
                            description: Text("Reconnect to read installed skills from your Gateway."))
                            .accessibilityIdentifier("skills.offlineEmpty")
                    }
                }
            }
            .padding(AppTheme.Metrics.screenPadding)
        }
        .background { AmbientGlow() }
        .foregroundStyle(theme.textPrimary.color)
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $store.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search skills")
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("skills.grid")
        .refreshable { if isConnected { await store.refresh() } }
        .task { if isConnected && !store.hasLoaded { await store.refresh() } }
        .sheet(item: $selectedSkill) { skill in
            NavigationStack {
                Group {
                    if let current = store.skills.first(where: { $0.id == skill.id }) {
                        SkillDetailView(skill: current, isStale: store.isStale)
                    } else {
                        ContentUnavailableView("Skill unavailable", systemImage: "square.grid.2x2",
                            description: Text("This skill is no longer in the Gateway's installed skills."))
                            .navigationTitle("Skill unavailable")
                    }
                }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedSkill = nil }.accessibilityIdentifier("skills.detail.done")
                        }
                    }
            }
        }
    }
}
