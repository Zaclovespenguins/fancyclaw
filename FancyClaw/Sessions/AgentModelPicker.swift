import ChatCore
import GatewayProtocol
import SwiftUI

struct AgentModelPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: SessionStore
    let sessionKey: String
    let onNewChat: () async -> Void

    private var session: SessionSummary { store.sessions.first(where: { $0.key == sessionKey }) ?? SessionSummary(key: sessionKey) }
    private var agentName: String {
        store.agents.first(where: { $0.id == session.agentId })?.name ?? session.agentId ?? "Assistant"
    }

    var body: some View {
        Menu {
            Section("Agent for a new chat") {
                ForEach(store.agents) { agent in
                    Button(agent.name ?? agent.id) {
                        store.selectedAgentID = agent.id
                        Task { await onNewChat() }
                    }
                }
            }
            Section("Model for this chat") {
                ForEach(store.models) { model in
                    Button {
                        Task { await store.setModel(model, for: session) }
                    } label: {
                        if session.model == model.selectionID { Label(model.name, systemImage: "checkmark") }
                        else { Text(model.name) }
                    }
                    .disabled(model.available == false)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(agentName).foregroundStyle(Color.primary).lineLimit(1)
                if !dynamicTypeSize.isAccessibilitySize, let model = session.model { Text("· \(model)").foregroundStyle(.secondary).lineLimit(1) }
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.subheadline)
            .frame(minHeight: 28)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("\(agentName). Choose agent or model")
        .accessibilityValue([agentName, session.model].compactMap { $0 }.joined(separator: ", "))
        .padding(.horizontal)
        .accessibilityIdentifier("chat.agentModel")
    }
}
