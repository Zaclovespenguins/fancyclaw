import SwiftUI

struct ChatConnectionMenu: View {
    let status: String
    let onDisconnect: () -> Void

    private var statusColor: Color {
        if status.localizedCaseInsensitiveContains("reconnect") { return .orange }
        if status.localizedCaseInsensitiveContains("offline") || status.localizedCaseInsensitiveContains("disconnect") {
            return .red
        }
        if status.localizedCaseInsensitiveContains("connect") { return .green }
        return .yellow
    }

    var body: some View {
        Menu {
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: onDisconnect)
        } label: {
            Label {
                Text(status)
                    .foregroundStyle(.primary)
            } icon: {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("Connection status: \(status)")
        .accessibilityIdentifier("chat.connectionStatus")
    }
}
