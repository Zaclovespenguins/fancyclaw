import SwiftUI
import ChatCore
import GatewayClient
import GatewayProtocol

struct ContentView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if model.isPreparing {
                ProgressView("Opening FancyClaw…")
                    .navigationTitle("FancyClaw")
                    .navigationBarTitleDisplayMode(.inline)
            } else if let conversation = model.conversation {
                ChatView(store: conversation, sessions: model.sessions, connectionStatus: model.status.rawValue,
                    onDisconnect: disconnect, onReconnect: { Task { await model.reconnect() } }, onSelectSession: { key in await model.selectSession(key) },
                    onNewChat: { await model.newChat() })
                    .id(conversation.sessionKey)
            } else {
                OnboardingView(onConnected: connected, initialProfile: model.initialProfile)
            }
        }
        .task { await model.prepare() }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setForeground(phase != .background) }
        }
        .alert("Connection issue", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func disconnect() { Task { await model.disconnect() } }

    private func connected(profile: GatewayProfile, connection: GatewayConnection, hello: HelloOK) {
        Task { await model.activate(profile: profile, connection: connection, hello: hello) }
    }
}

#Preview { ContentView() }
