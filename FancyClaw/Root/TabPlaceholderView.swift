import DesignSystem
import SwiftUI
import SystemIntegration

/// Stand-in content for a tab whose redesign slice hasn't landed yet. Theme-token text over the glow,
/// scrollable so large text sizes reflow instead of clipping.
struct TabPlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Centered when it fits; scrolls at large text sizes instead of clipping. One layout for every size,
        // so the text element stays the same while Dynamic Type changes.
        GeometryReader { proxy in
            ScrollView {
                content.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { AmbientGlow() }
        .navigationTitle(title)
    }

    private var content: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(theme.textSecondary.color)
                .accessibilityHidden(true)
            Text("\(title) is coming soon")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(theme.textSecondary.color)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppTheme.Metrics.homePadding)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

/// Home until Slice R4: a placeholder with the avatar button that opens Settings.
struct HomePlaceholderView: View {
    let model: AppModel

    var body: some View {
        TabPlaceholderView(title: "Home", systemImage: "house",
                           message: "Open a conversation from Chats, or start one with the compose button.")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.router.openSettings() } label: { ProfileAvatar() }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("home.settings")
                }
            }
    }
}

/// The person's avatar: their name's initial from Settings, or a person symbol.
struct ProfileAvatar: View {
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Group {
            if let initial = AgentAvatar.initial(for: userName) {
                Text(initial).font(.callout.weight(.semibold))
            } else {
                Image(systemName: "person.fill").font(.callout)
            }
        }
        .foregroundStyle(theme.textPrimary.color)
        .frame(width: size, height: size)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.circle)
    }
}
