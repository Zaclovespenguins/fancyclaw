import DesignSystem
import SwiftUI

/// "Thinking…" with a shimmer sweeping across the text; static when Reduce Motion is on.
struct ChatThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @State private var sweep = false

    var body: some View {
        Text("Thinking…")
            .font(.callout)
            .foregroundStyle(theme.textSecondary.color)
            .overlay {
                if !reduceMotion {
                    Text("Thinking…")
                        .font(.callout)
                        .foregroundStyle(theme.textPrimary.color)
                        .mask {
                            GeometryReader { geometry in
                                LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geometry.size.width * 0.6)
                                    .offset(x: sweep ? geometry.size.width : -geometry.size.width * 0.6)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Assistant is thinking")
            .accessibilityIdentifier("chat.thinking")
    }
}
