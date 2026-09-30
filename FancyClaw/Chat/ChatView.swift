import ChatCore
import DesignSystem
import SwiftUI

struct ChatView: View {
    let store: ConversationStore
    let connectionStatus: String
    let onDisconnect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var isFollowingLatest = true

    init(
        store: ConversationStore,
        connectionStatus: String = "Connected",
        onDisconnect: @escaping () -> Void = {}
    ) {
        self.store = store
        self.connectionStatus = connectionStatus
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
                        ChatMessageRow(message: message)
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
        .onChange(of: store.messages.count) { scrollToLatest() }
        .onChange(of: store.messages.last?.text) { scrollToLatest() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("chat.error")
                }

                ChatComposer(isStreaming: store.isStreaming, send: send, stop: stop)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(.bar)
        }
        .navigationTitle("FancyClaw")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ChatConnectionMenu(status: connectionStatus, onDisconnect: onDisconnect)
            }
        }
        .task {
            await store.start()
        }
    }

    private func scrollToLatest() {
        guard isFollowingLatest, !store.messages.isEmpty else { return }
        if reduceMotion {
            scrollPosition.scrollTo(edge: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    private func send(_ text: String) {
        Task { await store.send(text) }
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
