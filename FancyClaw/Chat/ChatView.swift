import ChatCore
import GatewayClient
import GatewayProtocol
import DesignSystem
import SwiftUI

struct ChatView: View {
    @Bindable var store: ConversationStore
    let sessions: SessionStore?
    let approvals: ApprovalStore?
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
        approvals: ApprovalStore? = nil,
        connectionStatus: String = "Connected",
        onDisconnect: @escaping () -> Void = {},
        onReconnect: @escaping () -> Void = {},
        onSelectSession: @escaping (String) async -> Void = { _ in },
        onNewChat: @escaping () async -> Void = {}
    ) {
        self.store = store
        self.sessions = sessions
        self.approvals = approvals
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
                        .frame(minHeight: 44)
                        .disabled(store.isLoadingHistory)
                        .accessibilityIdentifier("chat.older")
                }
                if store.messages.isEmpty && (approvals?.approvals(for: store.sessionKey).isEmpty ?? true) {
                    ContentUnavailableView(
                        connectionStatus == "Connected" ? "Start a conversation" : "No saved messages",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(connectionStatus == "Connected"
                            ? "Send a message to your OpenClaw assistant."
                            : "Reconnect from the connection menu to load this chat.")
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
                if let approvals {
                    ForEach(approvals.approvals(for: store.sessionKey)) { approval in
                        ApprovalCard(approval: approval, store: approvals, isConnected: connectionStatus == "Connected")
                            .id("approval:\(approval.id)")
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
        .onChange(of: approvals?.approvals.count) { scrollToLatest() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let sessions {
                    AgentModelPicker(store: sessions, sessionKey: store.sessionKey, onNewChat: onNewChat)
                }
                if let errorMessage = store.errorMessage {
                    ErrorBanner(message: errorMessage) { store.errorMessage = nil }
                        .padding(.horizontal)
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
                Button { showingSessions = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sidebar.left")
                        if let count = approvals?.pendingCount(), count > 0 {
                            Circle().fill(.tint).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                }
                    .accessibilityLabel("Chats")
                    .accessibilityValue("\(approvals?.pendingCount() ?? 0) pending command approvals")
                    .accessibilityIdentifier("chat.sessions")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatConnectionMenu(status: connectionStatus, onDisconnect: onDisconnect, onReconnect: onReconnect)
            }
        }
        .sheet(isPresented: $showingSessions) {
            if let sessions {
                SessionsDrawer(store: sessions, approvals: approvals, selectedKey: store.sessionKey,
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
        guard isFollowingLatest, !isPaging else { return }
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

#Preview("Conversation thread") {
    @Previewable @State var store: ConversationStore = {
        // An unconnected, ephemeral identity keeps the preview independent of saved profiles.
        let connection = GatewayConnection(identity: .generate())
        let store = ConversationStore(connection: connection)
        store.reconcileHistory([
            ChatMessage(role: .user, content: [
                .text("Can you help me plan the next update for FancyClaw?")
            ], metadata: .init(id: "preview-user-1")),
            ChatMessage(role: .assistant, content: [
                .text("""
                Absolutely. I'd focus on three things:

                - **Connection recovery** so a dropped signal never loses a draft.
                - **Rich replies** with readable code, tables, and tool results.
                - **Accessibility** so the whole conversation works at larger text sizes.

                Which one would you like to start with?
                """)
            ], metadata: .init(id: "preview-assistant-1")),
            ChatMessage(role: .user, content: [
                .text("Let's start with connection recovery. Check the notes I attached."),
                .media(.init(kind: .file, mimeType: "text/plain", fileName: "recovery-notes.txt", sizeBytes: 2048))
            ], metadata: .init(id: "preview-user-2")),
            ChatMessage(role: .assistant, content: [
                .toolCall(.init(id: "preview-read-notes", name: "read_file",
                               arguments: .object(["path": .string("recovery-notes.txt")]))),
                .text("I'll read the notes and turn them into a short checklist.")
            ], metadata: .init(id: "preview-assistant-2")),
            ChatMessage(role: .toolResult, content: [
                .text("Keep drafts per chat. Retry with the original message key. Refresh history after reconnecting.")
            ], toolCallId: "preview-read-notes", toolName: "read_file",
               metadata: .init(id: "preview-tool-result")),
            ChatMessage(role: .assistant, content: [
                .text("""
                Here's the checklist from your notes:

                | Situation | Expected behavior |
                | --- | --- |
                | Signal drops | Keep the draft |
                | Send is retried | Reuse the message key |
                | Connection returns | Refresh chat history |

                > The Gateway remains the source of truth.
                """)
            ], metadata: .init(id: "preview-assistant-3")),
            ChatMessage(role: .user, content: [
                .text("Show me what the retry call would look like in Swift.")
            ], metadata: .init(id: "preview-user-3")),
            ChatMessage(role: .assistant, content: [
                .text("""
                Reuse the original key so a retry doesn't create a second message:

                ```swift
                await conversation.retry(
                    idempotencyKey: originalMessageKey
                )
                ```

                The draft stays available while the connection recovers. Once history confirms the message, its pending send can be cleared.
                """)
            ], metadata: .init(id: "preview-assistant-4"))
        ])
        return store
    }()

    NavigationStack {
        ChatView(store: store)
    }
    .onDisappear { store.stopListening() }
}
