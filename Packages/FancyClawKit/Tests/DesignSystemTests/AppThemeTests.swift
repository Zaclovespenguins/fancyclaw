import Testing
@testable import DesignSystem

struct AppThemeTests {
    private let theme = AppTheme.coral

    @Test func defaultThemeIsCoral() {
        #expect(ThemeID.default == .coral)
        #expect(ThemeID(rawValue: ThemeID.default.rawValue)?.theme.id == .coral)
        #expect(ThemeID.coral.displayName == "Coral")
        #expect(ThemeID.storageKey == "themeID")
    }

    @Test func darkTokensMatchTheHandoff() {
        #expect(theme.bg.dark == .init(hex: 0x0B0B0F))
        #expect(theme.textPrimary.dark == .init(hex: 0xF5F5F7))
        #expect(theme.accent.dark == .init(hex: 0xF28A5E))
        #expect(theme.online.dark == .init(hex: 0x5CD98A))
    }

    @Test func everyTokenHasDistinctLightAndDarkValuesExceptTheAvatar() {
        let tokens = [theme.bg, theme.textPrimary, theme.textSecondary, theme.textTertiary, theme.placeholder,
                      theme.accent, theme.accentText, theme.online, theme.warning, theme.danger, theme.diffAdd, theme.diffRemove,
                      theme.glowCoral, theme.glowViolet, theme.glowBlue]
        for token in tokens { #expect(token.light != token.dark) }
    }

    @Test func lightGlowIsSofterThanDark() {
        for glow in [theme.glowCoral, theme.glowViolet, theme.glowBlue] {
            #expect(glow.light.opacity < glow.dark.opacity)
        }
    }

    @Test(arguments: ["textPrimary", "textSecondary", "textTertiary", "accent", "accentText", "danger", "warning"])
    func textTokensPassSmallTextContrastOnTheBase(_ name: String) throws {
        let tokens = ["textPrimary": theme.textPrimary, "textSecondary": theme.textSecondary,
                      "textTertiary": theme.textTertiary, "accent": theme.accent, "accentText": theme.accentText,
                      "danger": theme.danger, "warning": theme.warning]
        let token = try #require(tokens[name])
        let light = ThemeColor.Components.contrast(token.light.over(theme.bg.light), theme.bg.light)
        let dark = ThemeColor.Components.contrast(token.dark.over(theme.bg.dark), theme.bg.dark)
        #expect(light >= 4.5, "light contrast \(light)")
        #expect(dark >= 4.5, "dark contrast \(dark)")
    }

    @Test func avatarInitialComesFromTheName() {
        #expect(AgentAvatar.initial(for: "claw") == "C")
        #expect(AgentAvatar.initial(for: "  9lives") == "9")
        #expect(AgentAvatar.initial(for: "") == nil)
        #expect(AgentAvatar.initial(for: nil) == nil)
        #expect(AgentAvatar.initial(for: "🙂") == nil)
    }
}
