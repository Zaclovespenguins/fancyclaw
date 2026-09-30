import ChatCore
import GatewayProtocol
import DesignSystem
import SwiftUI

struct ChatView: View {
    @Bindable var store: ConversationStore
    let sessions: SessionStore?
    let onSelectSession: (String) async -> Void
    let onNewChat: () async -> Void
    let connectionStatus: String
    let onDisconnect: () -> Void
    let onReconnect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var isFollowingLatest = true
    @State private var showingSessions = false
    @State private var isPaging = false

    init(
        store: ConversationStore,
        sessions: SessionStore? = nil,
        connectionStatus: String = "Connected",
        onDisconnect: @escaping () -> Void = {},
        onReconnect: @escaping () -> Void = {},
        onSelectSession: @escaping (String) async -> Void = { _ in },
        onNewChat: @escaping () async -> Void = {}
    ) {
        self.store = store
        self.sessions = sessions
        self.onSelectSession = onSelectSession
        self.onNewChat = onNewChat
        self.connectionStatus = connectionStatus
        self.onDisconnect = onDisconnect
        self.onReconnect = onReconnect
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.hasMoreHistory {
                    Button("Load older messages") { loadOlder() }
                        .disabled(store.isLoadingHistory)
                        .accessibilityIdentifier("chat.older")
                }
                if store.messages.isEmpty {
                    ContentUnavailableView(
                        "Start a conversation",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Send a message to your OpenClaw assistant.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .accessibilityIdentifier("chat.emptyState")
                } else {
                    ForEach(store.messages) { message in
                        ChatMessageRow(message: message, gatewayBaseURL: store.gatewayBaseURL, loadImage: { [store] media in
                            try await store.imageData(media)
                        })
                            .id(message.id)
                    }

                    if store.isStreaming,
                       store.messages.last(where: { $0.role == .assistant })?.isStreaming != true {
                        ChatThinkingIndicator()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .accessibilityIdentifier("chat.transcript")
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height <= geometry.containerSize.height
                || geometry.contentSize.height - geometry.visibleRect.maxY <= 96
        } action: { _, isAtBottom in
            isFollowingLatest = isAtBottom
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.minY <= 20
        } action: { previous, atTop in
            if atTop && !previous { loadOlder() }
        }
        .onChange(of: store.messages.count) { scrollToLatest() }
        .onChange(of: store.messages.last?.text) { scrollToLatest() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let sessions {
                    AgentModelPicker(store: sessions, sessionKey: store.sessionKey, onNewChat: onNewChat)
                }
                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("chat.error")
                }

                ChatComposer(isStreaming: store.isStreaming, attachments: $store.draftAttachments,
                             limits: { await store.attachmentLimits() }, send: send, stop: stop)
                    .id(store.sessionKey)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(.bar)
        }
        .navigationTitle(sessions?.sessions.first(where: { $0.key == store.sessionKey })?.title ?? "FancyClaw")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Chats", systemImage: "sidebar.left") { showingSessions = true }
                    .accessibilityIdentifier("chat.sessions")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatConnectionMenu(status: connectionStatus, onDisconnect: onDisconnect, onReconnect: onReconnect)
            }
        }
        .sheet(isPresented: $showingSessions) {
            if let sessions {
                SessionsDrawer(store: sessions, selectedKey: store.sessionKey,
                    onSelect: onSelectSession, onNewChat: onNewChat)
            }
        }
        .task {
            await store.start()
        }
    }

    private func loadOlder() {
        guard store.hasMoreHistory, !isPaging, !store.isLoadingHistory else { return }
        isPaging = true
        let firstID = store.messages.first?.id
        Task {
            await store.loadOlderHistory()
            if let firstID { scrollPosition.scrollTo(id: firstID, anchor: .top) }
            isPaging = false
        }
    }

    private func scrollToLatest() {
        guard isFollowingLatest, !isPaging, !store.messages.isEmpty else { return }
        if reduceMotion {
            scrollPosition.scrollTo(edge: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    private func send(_ text: String, attachments: [PreparedAttachment]) async -> Bool {
        await store.send(text, attachments: attachments)
    }

    private func stop() {
        Task { await store.abort() }
    }
}

#Preview {
    NavigationStack {
        ContentUnavailableView("Chat preview", systemImage: "bubble.left")
            .navigationTitle("FancyClaw")
    }
}
