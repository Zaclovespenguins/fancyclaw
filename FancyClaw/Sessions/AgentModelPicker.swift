import ChatCore
import GatewayProtocol
import SwiftUI

/// The agent and model choices behind a tap on the chat title ("Agent for a new chat", "Model for this chat").
struct AgentModelMenuContent: View {
    @Bindable var store: SessionStore
    let sessionKey: String
    let onNewChat: () async -> Void

    private var session: SessionSummary { store.sessions.first(where: { $0.key == sessionKey }) ?? SessionSummary(key: sessionKey) }

    var body: some View {
        Section("Agent for a new chat") {
            ForEach(store.agents) { agent in
                Button(agent.name?.nilIfBlank ?? agent.id.capitalized) {
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
    }

    /// The display name of the agent behind `sessionKey`, or nil while the Gateway hasn't said.
    static func agentName(in store: SessionStore, sessionKey: String) -> String? {
        let session = store.sessions.first(where: { $0.key == sessionKey })
        let agentID = session?.agentId ?? store.selectedAgentID
        guard let agentID else { return nil }
        return store.agents.first(where: { $0.id == agentID })?.name?.nilIfBlank ?? agentID.capitalized
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
