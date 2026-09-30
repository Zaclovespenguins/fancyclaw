import SwiftUI
import Textual

struct MarkdownCodeBlock: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    @State private var copied = false

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
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .font(.caption)
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
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.2))
                .allowsHitTesting(false)
        }
    }

    private func copy() {
        configuration.codeBlock.copyToPasteboard()
        copied = true
    }
}
