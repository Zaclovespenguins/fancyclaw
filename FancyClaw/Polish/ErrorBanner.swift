import SwiftUI

/// Keeps failures readable without covering the conversation or relying on color.
struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
        }
        .foregroundStyle(Color.primary)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.4)) }
        .accessibilityElement(children: .contain)
        .onChange(of: message, initial: true) { _, message in
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
