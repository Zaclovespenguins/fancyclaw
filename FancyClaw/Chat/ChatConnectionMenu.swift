import SwiftUI

struct ChatConnectionMenu: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let status: String
    let onDisconnect: () -> Void
    var onReconnect: () -> Void = {}

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
            Text(status)
            Toggle("Haptics", isOn: $hapticsEnabled)
            if status != "Connected" {
                Button("Reconnect", systemImage: "arrow.clockwise", action: onReconnect)
            }
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: onDisconnect)
        } label: {
            Label {
                Text(dynamicTypeSize.isAccessibilitySize ? "" : status)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: status == "Connected" ? "checkmark.circle.fill" : "wifi.exclamationmark")
                    .foregroundStyle(statusColor)
            }
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
                .fixedSize()
                .frame(minWidth: 24, minHeight: 30)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("Connection status: \(status)")
        .accessibilityIdentifier("chat.connectionStatus")
    }
}
