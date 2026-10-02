import DesignSystem
import SwiftUI

struct ChatToolDetail: View {
    let title: String
    let text: String
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary.color)
            ScrollView(.horizontal) {
                Text(text).font(.caption.monospaced()).foregroundStyle(theme.textPrimary.color).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
