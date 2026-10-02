import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(conversation.messages) { MessageView(message: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.bottom)
        .background(AmbientGlow())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { inputBar }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44).glass(in: Circle(), interactive: true)
            }
            Spacer()
            VStack(spacing: 2) {
                AgentAvatar(size: 30)
                Text(conversation.title).font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Menu {
                Button("Rename", systemImage: "pencil") { }
                Button("Share", systemImage: "square.and.arrow.up") { }
                Button("Delete", systemImage: "trash", role: .destructive) { }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44).glass(in: Circle(), interactive: true)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(stops: [.init(color: Theme.bg.opacity(0.85), location: 0.55), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea().padding(.bottom, -24)
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.08), in: Circle())
            }
            TextField("Ask a follow-up", text: $draft, axis: .vertical)
                .font(.system(size: 16)).lineLimit(1...5)
            Button { } label: {
                Image(systemName: draft.isEmpty ? "waveform" : "arrow.up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 40, height: 40).background(Theme.textPrimary, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .padding(7)
        .frame(minHeight: 54)
        .glass(in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct MessageView: View {
    let message: Message

    var body: some View {
        switch message.content {
        case .text(let s):
            if message.role == .user {
                Text(s).font(.system(size: 16)).lineSpacing(4)
                    .padding(.vertical, 11).padding(.horizontal, 15)
                    .background(Theme.accent.opacity(0.32), in: UnevenRoundedRectangle(
                        topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous))
                    .containerRelativeFrame(.horizontal, alignment: .trailing) { w, _ in w * 0.82 }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(s).font(.system(size: 16)).lineSpacing(3)
            }

        case .toolSummary(let icon, let text):
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13))
                Text(text).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).opacity(0.6)
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.leading, 10).padding(.trailing, 12).frame(height: 34)
            .background(Color.white.opacity(0.07), in: Capsule())

        case .link(let title, let meta, let domain):
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 104) // OpenGraph image
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(meta).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.15)).frame(width: 14, height: 14)
                        Text(domain)
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.top, 5)
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        case .file(let name, let detail):
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 22))
                    .frame(width: 34, height: 40).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "arrow.down.to.line").font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32).background(.white.opacity(0.1), in: Circle())
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        case .steps(let steps, let elapsed):
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("WORKING · \(steps.filter { $0.state == .done }.count + 1) OF \(steps.count)")
                        .font(.system(size: 13, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(elapsed).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.textTertiary)
                }
                .padding(.bottom, 1)
                ForEach(steps) { s in
                    HStack(spacing: 10) {
                        Group {
                            switch s.state {
                            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Theme.accent)
                            case .active: ProgressView().controlSize(.mini).tint(Theme.accent)
                            case .pending: Circle().stroke(.white.opacity(0.22), lineWidth: 1.5)
                            }
                        }
                        .frame(width: 18, height: 18)
                        Text(s.text).font(.system(size: 15))
                            .foregroundStyle(s.state == .pending ? Theme.textTertiary : Theme.textPrimary)
                    }
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        case .diff(let file, let lines):
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("{ }").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 26, height: 26).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    Text(file).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("+\(lines.filter { $0.kind == .add }.count)").foregroundStyle(Theme.diffAdd)
                    Text("−\(lines.filter { $0.kind == .remove }.count)").foregroundStyle(Theme.diffRemove)
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(.vertical, 11).padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { l in
                        HStack(spacing: 10) {
                            Text(l.kind == .add ? "+" : l.kind == .remove ? "−" : " ").opacity(0.7)
                            Text(l.text)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(l.kind == .add ? Theme.diffAdd : l.kind == .remove ? Theme.diffRemove : Theme.textSecondary)
                        .frame(height: 20).padding(.horizontal, 14)
                        .background(l.kind == .add ? Color.green.opacity(0.14) : l.kind == .remove ? Color.red.opacity(0.16) : .clear)
                    }
                }
                .padding(.vertical, 8)
                .background(.black.opacity(0.35))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        case .approval(let title, let command):
            ApprovalCard(title: title, command: command)
        }
    }
}

struct ApprovalCard: View {
    let title: String
    let command: String
    @State private var resolved: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let resolved {
                Label(resolved ? "Approved · \(command)" : "Denied", systemImage: resolved ? "checkmark" : "xmark")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Text("APPROVAL NEEDED").font(.system(size: 13, weight: .semibold)).kerning(0.4)
                }
                .foregroundStyle(Theme.accentText)
                Text(title).font(.system(size: 16, weight: .semibold)).padding(.top, 6)
                Text(command).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9).padding(.horizontal, 12)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 10)
                HStack(spacing: 8) {
                    Button { withAnimation(.smooth) { resolved = false } } label: {
                        Text("Deny").frame(maxWidth: .infinity, minHeight: 40).background(.white.opacity(0.1), in: Capsule())
                    }
                    Button { withAnimation(.smooth) { resolved = true } } label: {
                        Text("Approve").foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 40).background(Theme.textPrimary, in: Capsule())
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Theme.accent.opacity(0.18))
        .sensoryFeedback(.success, trigger: resolved)
    }
}

#Preview { NavigationStack { ChatView(conversation: MockData.conversations[0]) }.preferredColorScheme(.dark) }
