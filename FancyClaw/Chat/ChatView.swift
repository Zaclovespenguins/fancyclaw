import ChatCore
import GatewayClient
import GatewayProtocol
import DesignSystem
import SwiftUI

struct ChatView: View {
    @Bindable var store: ConversationStore
    let sessions: SessionStore?
    let approvals: ApprovalStore?
    let onNewChat: () async -> Void
    let connectionStatus: String
    /// An approval to scroll to when the chat opens (approval Review).
    let focusApproval: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var isFollowingLatest = true
    @State private var isPaging = false
    /// True from opening an approval Review until the person scrolls; keeps the card in view while history loads.
    @State private var isFocusingApproval = false

    init(
        store: ConversationStore,
        sessions: SessionStore? = nil,
        approvals: ApprovalStore? = nil,
        connectionStatus: String = "Connected",
        focusApproval: String? = nil,
        onNewChat: @escaping () async -> Void = {}
    ) {
        self.store = store
        self.sessions = sessions
        self.approvals = approvals
        self.onNewChat = onNewChat
        self.connectionStatus = connectionStatus
        self.focusApproval = focusApproval
    }

    private var sessionApprovals: [ConversationApproval] { approvals?.approvals(for: store.sessionKey) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBar(store: store, sessions: sessions, onNewChat: onNewChat)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if store.hasMoreHistory {
                        Button("Load older messages") { loadOlder() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accentText.color)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(store.isLoadingHistory)
                            .accessibilityIdentifier("chat.older")
                    }
                    if store.messages.isEmpty && sessionApprovals.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.messages) { message in
                            ChatMessageRow(message: message, gatewayBaseURL: store.gatewayBaseURL, loadImage: { [store] media in
                                try await store.imageData(media)
                            }, loadFile: { [store] media in
                                try await store.fileData(media)
                            }, onRetry: { [store, id = message.id] in
                                Task { await store.retry(messageID: id) }
                            })
                                .id(message.id)
                        }

                        if store.isStreaming,
                           store.messages.last(where: { $0.role == .assistant })?.isStreaming != true {
                            ChatThinkingIndicator()
                        }
                    }
                    if let approvals {
                        ForEach(sessionApprovals) { approval in
                            ApprovalCard(approval: approval, store: approvals, isConnected: connectionStatus == "Connected")
                                .id("approval:\(approval.id)")
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, AppTheme.Metrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            // Clip the scrolling viewport, including its safe-area overflow, so offscreen text does not remain
            // exposed beneath the opaque status/header area and floating composer.
            .clipped()
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat.transcript")
            // Flat theme base: the ambient glow behind transcript text made the accessibility audit's contrast fail.
            .background { theme.bg.color.ignoresSafeArea() }
            .onScrollPhaseChange { _, phase in
                // A person's own scrolling takes over from the approval Review focus.
                if phase == .interacting { isFocusingApproval = false }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height <= geometry.containerSize.height
                    || geometry.contentSize.height - geometry.visibleRect.maxY <= 96
            } action: { _, isAtBottom in
                if !isFocusingApproval { isFollowingLatest = isAtBottom }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.minY <= 20
            } action: { previous, atTop in
                if atTop && !previous && !isFocusingApproval { loadOlder() }
            }
            .onChange(of: store.messages.count) { scrollToLatest() }
            .onChange(of: store.messages.last?.text) { scrollToLatest() }
            .onChange(of: approvals?.approvals.count) { scrollToLatest() }
        }
        .background { theme.bg.color.ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let errorMessage = store.errorMessage {
                    ErrorBanner(message: errorMessage) { store.errorMessage = nil }
                        .accessibilityIdentifier("chat.error")
                }
                if let sessions, let errorMessage = sessions.errorMessage {
                    ErrorBanner(message: errorMessage) { sessions.errorMessage = nil }
                        .accessibilityIdentifier("chat.sessionError")
                }

                ChatComposer(isStreaming: store.isStreaming, attachments: $store.draftAttachments,
                             limits: { await store.attachmentLimits() }, send: send, stop: stop)
                    .id(store.sessionKey)
            }
            .padding(.horizontal, AppTheme.Metrics.screenPadding)
            .padding(.bottom, 8)
            .background(alignment: .bottom) {
                LinearGradient(colors: [theme.bg.color.opacity(0), theme.bg.color.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -16)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .enableSwipeBack()
        .task {
            await store.start()
        }
        .task(id: focusApproval) {
            guard focusApproval != nil else { return }
            // Approval Review: stop following the latest message and bring the card into view.
            isFollowingLatest = false
            isFocusingApproval = true
            focusOnApproval()
        }
        // History and the card itself may arrive after the chat appears; re-aim until the person scrolls.
        .onChange(of: store.messages.count) { focusOnApproval(afterLayout: true) }
        .onChange(of: sessionApprovals.map(\.id)) { focusOnApproval(afterLayout: true) }
        .onChange(of: store.isLoadingHistory) { focusOnApproval(afterLayout: true) }
    }

    private var emptyState: some View {
        let connected = connectionStatus == "Connected"
        return VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(theme.textSecondary.color)
                .accessibilityHidden(true)
            Text(connected ? "Start a conversation" : "No saved messages")
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary.color)
            Text(connected ? "Send a message to your OpenClaw assistant." : "Reconnect from Settings to load this chat.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.emptyState")
    }

    private func focusOnApproval(afterLayout: Bool = false) {
        guard isFocusingApproval, let focusApproval,
              sessionApprovals.contains(where: { $0.id == focusApproval }) else { return }
        let target = "approval:\(focusApproval)"
        if afterLayout {
            // Let the new rows lay out first, so the target id resolves at its final position.
            Task { @MainActor in
                await Task.yield()
                guard isFocusingApproval else { return }
                scrollPosition.scrollTo(id: target, anchor: .center)
            }
        } else {
            scrollPosition.scrollTo(id: target, anchor: .center)
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
        guard isFollowingLatest, !isPaging, !isFocusingApproval else { return }
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
