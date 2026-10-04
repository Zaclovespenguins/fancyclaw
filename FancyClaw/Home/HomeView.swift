import ChatCore
import DesignSystem
import GatewayClient
import GatewayProtocol
import SwiftUI
import SystemIntegration

struct HomeView: View {
    let model: AppModel
    @Environment(\.appTheme) private var theme
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @State private var sheetApproval: ConversationApproval?

    private var pendingApprovals: [ConversationApproval] {
        model.approvals?.approvals.filter { $0.status.isPending } ?? []
    }

    private var running: [HomeRunningRow] {
        HomePresentation.running(sessions: model.sessions?.sessions ?? [], runs: model.runActivities?.activeRuns ?? [],
                                 terminalIDs: model.runActivities?.terminalRunIDs ?? [], approvals: pendingApprovals)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                statusPill.padding(.top, 14)
                HomePromptCard(draft: model.homeDraft, models: model.sessions?.models ?? [], agentName: model.homeAgentName,
                               connected: model.status == .connected, limits: { await model.homeAttachmentLimits() },
                               submit: { await model.submitHomeDraft() }, edit: model.editHomeAsNewTask)
                    .padding(.top, 20)
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }.padding(.top, 12)
                }
                if let sessions = model.sessions, let message = sessions.errorMessage, message != model.homeDraft.errorMessage {
                    ErrorBanner(message: message) { sessions.errorMessage = nil }.padding(.top, 12)
                }
                if !pendingApprovals.isEmpty {
                    Text("Needs you").sectionHeader()
                    VStack(spacing: 10) {
                        ForEach(pendingApprovals) { approval in
                            HomeApprovalRow(approval: approval) {
                                Task { if !(await model.review(approval)) { sheetApproval = approval } }
                            }
                        }
                    }
                }
                if !running.isEmpty {
                    Text("Running").sectionHeader()
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(running) { row in
                                HomeRunningCard(row: row) { Task { await model.open(sessionKey: row.sessionKey) } }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("home.running")
                }
                HStack {
                    Text("Recent").font(.title3.bold())
                    Spacer()
                    Button("See all") { model.router.selectedTab = .chats }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("home.seeAll")
                }
                .padding(.top, AppTheme.Metrics.sectionSpacing)
                .padding(.bottom, 10)
                recent
            }
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, AppTheme.Metrics.homePadding)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientGlow() }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refreshHome() }
        .accessibilityIdentifier("home.scroll")
        .sheet(item: $sheetApproval) { selected in
            NavigationStack {
                ScrollView {
                    if let store = model.approvals, let live = store.approvals.first(where: { $0.id == selected.id }) {
                        ApprovalCard(approval: live, store: store, isConnected: model.status == .connected)
                            .padding(20)
                    }
                }
                .background(theme.bg.color)
                .navigationTitle("Review command")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetApproval = nil } } }
            }
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.textSecondary.color)
                    Text(HomePresentation.greeting(at: context.date, name: userName))
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.greeting")
                }
                Spacer(minLength: 0)
                Button { model.router.openSettings() } label: {
                    ProfileAvatar().glass(in: .circle, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home.settings")
            }
        }
    }

    private var statusPill: some View {
        Button { if model.status != .connected { Task { await model.reconnect() } } } label: {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.footnote).fixedSize(horizontal: false, vertical: true)
                if model.status == .offline { Image(systemName: "arrow.clockwise") }
            }
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(theme.bg.color, in: Capsule())
            .glass(in: .capsule, interactive: model.status != .connected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.status")
        .accessibilityHint(model.status == .connected ? "" : "Reconnect to your Gateway")
    }

    private var statusText: String {
        switch model.status {
        case .connected: model.homeAgentName + " is online" + (model.gatewayHost.map { " · " + $0 } ?? "")
        case .reconnecting: "Reconnecting…"
        case .offline: "Offline · Tap to reconnect"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: theme.online.color
        case .reconnecting: theme.warning.color
        case .offline: theme.textTertiary.color
        }
    }

    @ViewBuilder private var recent: some View {
        let rows = HomePresentation.recent(model.sessions?.sessions ?? [])
        if rows.isEmpty {
            Text(model.status == .connected ? "Your conversations will appear here. Start a task above." : "No cached chats yet. Reconnect to load your conversations.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary.color)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(in: .rect(cornerRadius: AppTheme.Radius.card))
                .accessibilityIdentifier("home.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { session in
                    Button { Task { await model.open(sessionKey: session.key) } } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title ?? "New chat").font(.callout.weight(.semibold))
                                if let time = session.lastActivityAt ?? session.updatedAt {
                                    Text(Date(timeIntervalSince1970: time / 1000), style: .relative)
                                        .font(.footnote).foregroundStyle(theme.textSecondary.color)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(theme.textSecondary.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityIdentifier("home.recent.\(session.key)")
                    if session.key != rows.last?.key { Divider().padding(.leading, 16) }
                }
            }
            .surface(in: .rect(cornerRadius: AppTheme.Radius.card))
        }
    }
}
