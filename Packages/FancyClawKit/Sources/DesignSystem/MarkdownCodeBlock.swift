import SwiftUI
import Textual

/// Tracks the transient "Copied" confirmation. `copyCount` advances on every copy so haptics and the reset
/// timer re-trigger even while the confirmation is still showing.
struct CopyFeedback: Equatable {
    static let resetDelay: Duration = .seconds(2)

    private(set) var copyCount = 0
    private(set) var isCopied = false

    mutating func recordCopy() {
        copyCount += 1
        isCopied = true
    }

    /// Clears the confirmation unless a newer copy has happened since `copy`.
    mutating func reset(afterCopy copy: Int) {
        if copy == copyCount { isCopied = false }
    }
}

struct MarkdownCodeBlock: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    @State private var feedback = CopyFeedback()
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    private var copied: Bool { feedback.isCopied }

    var body: some View {
        // The outer Overflow excludes the entire card from the document selection overlay.
        // Selection stays local to the inner code scroller, leaving the header button tappable.
        Overflow { state in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(configuration.languageHint ?? "Code")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copied ? "Code copied" : "Copy code")
                        .accessibilityIdentifier("markdown.copyCode")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                Overflow {
                    configuration.label
                        .monospaced()
                        .textual.fontScale(0.88)
                        .textual.lineSpacing(.fontScaled(0.25))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                }
                .textual.textSelection(.enabled)
                .background(.background.secondary)
            }
            .frame(width: state.containerWidth, alignment: .leading)
        }
        .textual.textSelection(.disabled)
        .sensoryFeedback(.success, trigger: feedback.copyCount) { _, _ in hapticsEnabled }
        // Restarts on every copy, so rapid taps keep the confirmation until two seconds after the last one.
        .task(id: feedback.copyCount) {
            let copy = feedback.copyCount
            guard feedback.isCopied else { return }
            try? await Task.sleep(for: CopyFeedback.resetDelay)
            if !Task.isCancelled { feedback.reset(afterCopy: copy) }
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.2))
                .allowsHitTesting(false)
        }
    }

    private func copy() {
        configuration.codeBlock.copyToPasteboard()
        feedback.recordCopy()
    }
}
