import ChatCore
import GatewayProtocol
import SwiftUI

struct SessionsDrawer: View {
    @Bindable var store: SessionStore
    let selectedKey: String
    let onSelect: (String) async -> Void
    let onNewChat: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SessionSummary?
    @State private var newLabel = ""
    @State private var pendingAction: SessionAction?
    @State private var isCreating = false

    private var groups: [(title: String, rows: [SessionSummary])] {
        let calendar = Calendar.current
        let rows = store.visibleSessions
        func group(_ row: SessionSummary) -> Int {
            if row.pinned == true { return 0 }
            let date = Date(timeIntervalSince1970: (row.lastActivityAt ?? row.updatedAt ?? 0) / 1000)
            if calendar.isDateInToday(date) { return 1 }
            if calendar.isDateInYesterday(date) { return 2 }
            return 3
        }
        return ["Pinned", "Today", "Yesterday", "Earlier"].enumerated().compactMap { index, title in
            let matching = rows.filter { group($0) == index }
            return matching.isEmpty ? nil : (title, matching)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.rows) { session in
                            Button {
                                dismiss()
                                Task { await onSelect(session.key) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title ?? "New chat").foregroundStyle(.primary)
                                        if let preview = session.lastMessagePreview {
                                            Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if session.key == selectedKey { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }
                            .accessibilityIdentifier("sessions.row.\(session.key)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { pendingAction = .delete(session) }
                                Button("Reset", systemImage: "arrow.counterclockwise") { pendingAction = .reset(session) }.tint(.orange)
                                Button("Rename", systemImage: "pencil") { beginRename(session) }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { beginRename(session) }
                                Button("Reset", systemImage: "arrow.counterclockwise") { pendingAction = .reset(session) }
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingAction = .delete(session) }
                            }
                        }
                    }
                }
                if store.hasMoreVisibleSessions {
                    Button("Load more chats") { Task { await store.loadMoreVisibleSessions() } }.disabled(store.isLoading || store.isSearching)
                }
                if store.isLoading || store.isSearching { ProgressView() }
            }
            .overlay {
                if store.visibleSessions.isEmpty && !store.isLoading && !store.isSearching && store.errorMessage == nil {
                    ContentUnavailableView(store.search.isEmpty ? "No chats yet" : "No matching chats",
                        systemImage: "bubble.left.and.bubble.right", description: Text("Start a new conversation."))
                }
            }
            .navigationTitle("Chats")
            .searchable(text: $store.search, prompt: "Search chats")
            .refreshable { await store.loadList(); await store.searchSessions() }
            .task(id: store.search) { await store.searchSessions() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") {
                        isCreating = true
                        Task {
                            await onNewChat()
                            isCreating = false
                            if store.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(isCreating)
                    .accessibilityIdentifier("sessions.new")
                }
            }
            .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Chat name", text: $newLabel).accessibilityIdentifier("sessions.name")
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let session = renaming { Task { await store.rename(session, label: newLabel) } }
                    renaming = nil
                }
                .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog(pendingAction?.title ?? "", isPresented: Binding(
                get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
            ), titleVisibility: .visible) {
                if let action = pendingAction {
                    Button(action.buttonTitle, role: .destructive) {
                        pendingAction = nil
                        Task {
                            switch action {
                            case .delete(let session): await store.delete(session)
                            case .reset(let session): await store.reset(session)
                            }
                        }
                    }
                }
            } message: {
                Text("This removes the chat’s messages from the Gateway and this device.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func beginRename(_ session: SessionSummary) { newLabel = session.title ?? ""; renaming = session }
}

private enum SessionAction {
    case delete(SessionSummary)
    case reset(SessionSummary)
    var title: String {
        switch self {
        case .delete: "Delete this chat?"
        case .reset: "Reset this chat?"
        }
    }
    var buttonTitle: String {
        switch self {
        case .delete: "Delete chat"
        case .reset: "Reset chat"
        }
    }
}
