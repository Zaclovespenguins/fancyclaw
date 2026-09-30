import SwiftUI

struct ChatComposer: View {
    let isStreaming: Bool
    let send: (String) -> Void
    let stop: () -> Void

    @State private var draft = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message FancyClaw", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityIdentifier("chat.composer")

            Button(isStreaming ? "Stop" : "Send",
                   systemImage: isStreaming ? "stop.fill" : "arrow.up",
                   action: isStreaming ? stop : submit)
                .labelStyle(.iconOnly)
                .buttonStyle(ChatComposerButtonStyle(role: isStreaming ? .stop : .send))
                .disabled(!isStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(isStreaming ? "chat.stop" : "chat.send")
                .accessibilityInputLabels(isStreaming ? ["Stop response", "Stop generating"] : ["Send message"])
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
    }

    private func submit() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isStreaming else { return }
        draft = ""
        send(message)
    }
}

private struct ChatComposerButtonStyle: ButtonStyle {
    enum Role: Equatable {
        case send
        case stop
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(role == .send ? Color.accentColor : Color.primary.opacity(0.75), in: Circle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentTransition(.symbolEffect(.replace))
    }
}
