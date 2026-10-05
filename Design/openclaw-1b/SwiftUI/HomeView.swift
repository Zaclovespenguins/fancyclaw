import SwiftUI

struct HomeView: View {
    @State private var prompt = ""
    @FocusState private var promptFocused: Bool
    @State private var path: [Conversation] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                statusPill.padding(.top, 14)
                promptCard.padding(.top, 20)

                if !MockData.approvals.isEmpty {
                    Text("Needs you").sectionHeader()
                    ForEach(MockData.approvals) { ApprovalRow(approval: $0) }
                }

                Text("Running").sectionHeader()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MockData.running) { RunningCard(task: $0) }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)

                Text("Recent").sectionHeader()
                recentList
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .background(AmbientGlow())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
        .refreshable { }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THURSDAY, OCT 2")
                    .font(.system(size: 13, weight: .semibold)).kerning(0.4)
                    .foregroundStyle(Theme.textSecondary)
                Text("Good evening, Sam")
                    .font(.system(size: 32, weight: .bold)).kerning(-0.6)
            }
            Spacer()
            Button { } label: {
                Text("S").font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .glass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.online).frame(width: 8, height: 8)
                .shadow(color: Theme.online, radius: 4)
            Text("Claw is online · studio-mini")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.vertical, 7).padding(.leading, 10).padding(.trailing, 12)
        .glass(in: Capsule())
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentAvatar(size: 26)
                Text("Claw").font(.system(size: 15, weight: .semibold))
            }
            TextField("What should I take care of?", text: $prompt, axis: .vertical)
                .font(.system(size: 22, weight: .medium)).kerning(-0.2)
                .lineLimit(2...5)
                .frame(minHeight: 56, alignment: .topLeading)
                .focused($promptFocused)
                .padding(.top, 12)
            HStack(spacing: 8) {
                Button { } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Menu {
                    Button("Opus") { }; Button("Sonnet") { }; Button("Haiku") { }
                } label: {
                    HStack(spacing: 6) {
                        Text("Opus"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                Spacer()
                Button { } label: {
                    Image(systemName: prompt.isEmpty ? "waveform" : "arrow.up")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Theme.textPrimary, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 14, trailing: 16))
        .glass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 20)
    }

    private var recentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(MockData.conversations.enumerated()), id: \.element.id) { i, c in
                NavigationLink(value: c) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text(c.updatedLabel).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < MockData.conversations.count - 1 {
                    Divider().overlay(Color.white.opacity(0.1)).padding(.leading, 16)
                }
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct ApprovalRow: View {
    let approval: Approval
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(approval.title).font(.system(size: 16, weight: .semibold))
                Text(approval.command).font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Review") { }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Theme.textPrimary, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.accent.opacity(0.4), lineWidth: 0.5))
    }
}

struct RunningCard: View {
    let task: AgentTask
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title).font(.system(size: 15, weight: .semibold))
            Text(task.detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            ProgressLine(value: task.progress).padding(.top, 11)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(width: 220, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview { NavigationStack { HomeView() }.preferredColorScheme(.dark) }
