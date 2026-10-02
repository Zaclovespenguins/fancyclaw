import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

/// The floating chat header: glass back button, avatar and title (tap for agent/model), and the ••• menu.
struct ChatTopBar: View {
    let store: ConversationStore
    let sessions: SessionStore?
    let onNewChat: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var buttonSize = 44
    @State private var isRenaming = false
    @State private var newLabel = ""
    @State private var pendingAction: ChatSessionAction?

    private var session: SessionSummary? { sessions?.sessions.first(where: { $0.key == store.sessionKey }) }
    private var title: String { session?.title ?? "New chat" }
    private var agentName: String? { sessions.flatMap { AgentModelMenuContent.agentName(in: $0, sessionKey: store.sessionKey) } }

    var body: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.textPrimary.color)
                    .frame(width: buttonSize, height: buttonSize)
                    .glass(in: .circle, interactive: true)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("chat.back")

            VStack(spacing: 2) {
                AgentAvatar(name: agentName, accessibilityLabel: agentName ?? "Assistant")
                titleMenu
            }
            .frame(maxWidth: .infinity)

            moreMenu
        }
        .padding(.horizontal, AppTheme.Metrics.screenPadding)
        .padding(.vertical, 6)
        .background(alignment: .top) {
            // Solid under the buttons, then fading out below them, so scrolled text never collides with the title.
            VStack(spacing: 0) {
                theme.bg.color
                LinearGradient(colors: [theme.bg.color, theme.bg.color.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
            .padding(.bottom, -28)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .alert("Rename chat", isPresented: $isRenaming) {
            TextField("Chat name", text: $newLabel).accessibilityIdentifier("chat.rename.name")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let session, let sessions { Task { await sessions.rename(session, label: newLabel) } }
            }
            .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(pendingAction?.title ?? "", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            if let action = pendingAction, let session, let sessions {
                Button(action.buttonTitle, role: .destructive) {
                    pendingAction = nil
                    Task {
                        switch action {
                        case .delete: await sessions.delete(session)
                        case .reset: await sessions.reset(session)
                        }
                    }
                }
                .accessibilityIdentifier("chat.confirm.\(action.rawValue)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the chat’s messages from the Gateway and this device.")
        }
    }

    @ViewBuilder
    private var titleMenu: some View {
        let label = HStack(spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            if sessions != nil {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.textSecondary.color)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        if let sessions {
            Menu {
                AgentModelMenuContent(store: sessions, sessionKey: store.sessionKey, onNewChat: onNewChat)
            } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint("Choose agent or model")
            .accessibilityValue([agentName, session?.model].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("chat.agentModel")
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat.title")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Rename", systemImage: "pencil") {
                newLabel = session?.title ?? ""
                isRenaming = true
            }
            Button("Reset", systemImage: "arrow.counterclockwise") { pendingAction = .reset }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingAction = .delete }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.textPrimary.color)
                .frame(width: buttonSize, height: buttonSize)
                .glass(in: .circle, interactive: true)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
        .accessibilityLabel("Chat options")
        .accessibilityIdentifier("chat.menu")
    }
}

enum ChatSessionAction: String {
    case delete, reset
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

extension View {
    /// Hiding the navigation bar disables the edge-swipe back gesture; turn it back on.
    func enableSwipeBack() -> some View { background(SwipeBackEnabler()) }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
