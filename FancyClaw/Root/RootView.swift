import ChatCore
import DesignSystem
import GatewayClient
import GatewayProtocol
import SwiftUI
import SystemIntegration

/// The connected app shell: Home, Chats, Skills, and Activity tabs plus a detached compose button.
struct RootView: View {
    let model: AppModel
    @State private var isComposing = false

    /// The compose button is a tab-bar item but never a selection, so it lives only in this view's enum.
    private enum Selection: Hashable {
        case tab(AppTab)
        case compose
    }

    private var selection: Binding<Selection> {
        Binding(get: { .tab(model.router.selectedTab) }, set: { newValue in
            switch newValue {
            case .tab(let tab): model.router.selectedTab = tab
            case .compose: compose()
            }
        })
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("Home", systemImage: "house", value: Selection.tab(.home)) {
                stack(.home) { HomeView(model: model) }
            }
            Tab("Chats", systemImage: "bubble.left", value: Selection.tab(.chats)) {
                stack(.chats) {
                    if let sessions = model.sessions {
                        SessionsList(store: sessions, approvals: model.approvals, selectedKey: model.conversation?.sessionKey,
                                     onSelect: { key in await model.open(sessionKey: key) },
                                     onNewChat: { await model.newChat() })
                    }
                }
            }
            .badge(model.approvals?.pendingCount() ?? 0)
            Tab("Skills", systemImage: "square.grid.2x2", value: Selection.tab(.skills)) {
                stack(.skills) {
                    if let skills = model.skills {
                        SkillsView(store: skills, isConnected: model.status == .connected,
                                   onReconnect: { await model.reconnect() })
                            .id(ObjectIdentifier(skills))
                    }
                }
            }
            Tab("Activity", systemImage: "waveform.path.ecg", value: Selection.tab(.activity)) {
                stack(.activity) {
                    TabPlaceholderView(title: "Activity", systemImage: "waveform.path.ecg",
                                       message: "A timeline of approvals, runs and replies will appear here.")
                }
            }
            // iOS 26 draws the search role as a detached glass circle; it starts a new chat instead of searching.
            Tab(value: Selection.compose, role: .search) {
                Color.clear
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.linkPreviewLoader, model.linkPreviewLoader)
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: Binding(get: { model.router.path(for: tab) }, set: { model.router.setPath($0, for: tab) })) {
            root()
                .navigationDestination(for: AppRoute.self) { route in destination(route) }
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .chat(let key, let focusApproval):
            ChatDestination(model: model, sessionKey: key, focusApproval: focusApproval)
        case .settings:
            SettingsView(model: model)
                .toolbar(.visible, for: .navigationBar)
        case .skill(let id):
            if let skill = model.skills?.skills.first(where: { $0.id == id }) {
                SkillDetailView(skill: skill, isStale: model.skills?.isStale == true)
            } else {
                ContentUnavailableView("Skill unavailable", systemImage: "square.grid.2x2")
            }
        }
    }

    private func compose() {
        guard !isComposing else { return }
        isComposing = true
        Task {
            await model.newChat()
            isComposing = false
        }
    }
}

/// Resolves a routed chat to its store. Stores are created by `AppModel.open`, never during view updates.
struct ChatDestination: View {
    let model: AppModel
    let sessionKey: String
    let focusApproval: String?

    var body: some View {
        Group {
            if let store = model.existingStore(for: sessionKey) {
                ChatView(store: store, sessions: model.sessions, approvals: model.approvals,
                         connectionStatus: model.status.rawValue, focusApproval: focusApproval,
                         onNewChat: { await model.newChat() })
                    // A reset session gets a fresh store; rebuild the chat's view state with it.
                    .id(ObjectIdentifier(store))
            } else {
                ProgressView("Opening chat…")
                    .task { await model.selectSession(sessionKey) }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
