import DesignSystem
import SwiftUI
import SystemIntegration

struct HomeRunningCard: View {
    let row: HomeRunningRow
    let open: () -> Void
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var cardWidth = 220

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
                Text(row.detail).font(.footnote).foregroundStyle(theme.textSecondary.color)
                ProgressView().tint(theme.accent.color).padding(.top, 3)
            }
            .multilineTextAlignment(.leading)
            .frame(width: cardWidth, alignment: .leading)
            .padding(16)
            .background(theme.bg.color, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            .glass(in: .rect(cornerRadius: AppTheme.Radius.card), interactive: true)
        }
        .buttonStyle(PressScale())
        .accessibilityIdentifier("home.run.\(row.sessionKey)")
    }
}
