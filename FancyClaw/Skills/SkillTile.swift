import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct SkillTile: View {
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .title2) private var iconSize = 42
    let skill: SkillStatus

    private var accent: Color {
        switch SkillAccent.forSkill(skill) {
        case .coral: theme.accent.color
        case .blue: theme.glowBlue.color
        case .green: theme.online.color
        case .violet: theme.glowViolet.color
        case .neutral: theme.textSecondary.color
        }
    }
    private var statusColor: Color {
        switch skill.availability {
        case .ready: theme.online.color
        case .disabled, .unknown: theme.textTertiary.color
        case .restricted, .excludedFromAgent, .missingRequirements, .unavailable: theme.warning.color
        }
    }
    private var iconOpacity: Double {
        // Unknown skills receive a stable neutral shade, independent of Swift's randomized hash seed.
        let shade = Double(skill.name.utf8.reduce(0) { ($0 + Int($1)) % 4 }) * 0.025
        return 0.12 + shade
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(skill.displayGlyph)
                    .font(.title2)
                    .frame(width: iconSize, height: iconSize)
                    .background(accent.opacity(iconOpacity), in: RoundedRectangle(cornerRadius: AppTheme.Radius.iconTile))
                    .opacity(skill.disabled == true ? 0.6 : 1)
                Spacer(minLength: 8)
                Circle().fill(statusColor).frame(width: 8, height: 8).padding(.top, 6)
            }
            Text(skill.name).font(.callout.weight(.semibold))
                .foregroundStyle(theme.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(skill.availability.label).font(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surface(in: RoundedRectangle(cornerRadius: AppTheme.Radius.card), opacity: 0.035)
        .glass(in: RoundedRectangle(cornerRadius: AppTheme.Radius.card), interactive: true)
    }
}
