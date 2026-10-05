import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

/// The Chats tab root: the former sessions drawer, now pushed inside the tab's own navigation stack.
struct SessionsList: View {
    @Environment(\.appTheme) private var theme
    @Bindable var store: SessionStore
    let approvals: ApprovalStore?
    let selectedKey: String?
    let onSelect: (String) async -> Void
    let onNewChat: () async -> Void
    @State private var renaming: SessionSummary?
    @State private var newLabel = ""
    @State private var pendingAction: SessionAction?
    @State private var isCreating = false

    private var groups: [(title: String, rows: [SessionSummary])] {
        SessionListPresentation.groups(store.visibleSessions)
    }

    var body: some View {
        List {
            if let error = store.errorMessage {
                ErrorBanner(message: error) { store.errorMessage = nil }
                    .listRowBackground(theme.bg.color)
            }
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.rows) { session in
                        Button {
                            Task { await onSelect(session.key) }
                        } label: {
                            SessionListRow(session: session, approvalCount: approvals?.pendingCount(for: session.key) ?? 0,
                                           selected: session.key == selectedKey)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.bg.color.opacity(0.75))
                        .accessibilityIdentifier("sessions.row.\(session.key)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { pendingAction = .delete(session) }
                            Button("Reset", systemImage: "arrow.counterclockwise") { pendingAction = .reset(session) }.tint(theme.warning.color)
                            Button("Rename", systemImage: "pencil") { beginRename(session) }.tint(theme.accent.color)
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { beginRename(session) }
                            Button("Reset", systemImage: "arrow.counterclockwise") { pendingAction = .reset(session) }
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingAction = .delete(session) }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.title3.bold())
                        .foregroundStyle(theme.textPrimary.color)
                        .textCase(nil)
                        .accessibilityIdentifier("sessions.group.\(group.title)")
                }
            }
            if store.hasMoreVisibleSessions {
                Button("Load more chats") { Task { await store.loadMoreVisibleSessions() } }
                    .frame(minHeight: 44)
                    .disabled(store.isLoading || store.isSearching)
                    .accessibilityIdentifier("sessions.loadMore")
                    .listRowBackground(theme.bg.color.opacity(0.75))
            }
            if store.isLoading || store.isSearching {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(theme.bg.color.opacity(0.75))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { AmbientGlow() }
        .foregroundStyle(theme.textPrimary.color)
        .accessibilityIdentifier("sessions.list")
        .overlay {
            if store.visibleSessions.isEmpty && !store.isLoading && !store.isSearching && store.errorMessage == nil {
                if store.search.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Use New chat to start a conversation."))
                        .accessibilityIdentifier("sessions.empty")
                } else {
                    ContentUnavailableView.search(text: store.search)
                        .accessibilityIdentifier("sessions.searchEmpty")
                }
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $store.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
        .refreshable { await store.loadList(); await store.searchSessions() }
        .scrollDismissesKeyboard(.interactively)
        .task(id: store.search) { await store.searchSessions() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat", systemImage: "square.and.pencil") {
                    isCreating = true
                    Task {
                        await onNewChat()
                        isCreating = false
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
                    perform(action)
                }
            }
        } message: {
            Text("This removes the chat’s messages from the Gateway and this device.")
        }
    }

    private func beginRename(_ session: SessionSummary) { newLabel = session.title ?? ""; renaming = session }

    private func perform(_ action: SessionAction) {
        Task {
            switch action {
            case .delete(let session): await store.delete(session)
            case .reset(let session): await store.reset(session)
            }
        }
    }
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
