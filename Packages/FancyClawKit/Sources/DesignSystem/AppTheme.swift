import SwiftUI
import UIKit

/// The themes a person can pick. Only Coral exists today; Settings shows a disabled picker for more.
public enum ThemeID: String, CaseIterable, Identifiable, Sendable {
    case coral

    public static let storageKey = "themeID"
    public static let `default`: ThemeID = .coral

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .coral: "Coral"
        }
    }
    public var theme: AppTheme {
        switch self {
        case .coral: .coral
        }
    }
}

/// A light/dark pair of sRGB values. Kept separate from `Color` so tokens are testable.
public struct ThemeColor: Hashable, Sendable {
    public struct Components: Hashable, Sendable {
        public var red: Double, green: Double, blue: Double, opacity: Double
        public init(hex: UInt32, opacity: Double = 1) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
            self.opacity = opacity
        }

        /// WCAG relative luminance, ignoring opacity.
        public var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        /// This color composited over an opaque background.
        public func over(_ background: Components) -> Components {
            var result = self
            result.red = red * opacity + background.red * (1 - opacity)
            result.green = green * opacity + background.green * (1 - opacity)
            result.blue = blue * opacity + background.blue * (1 - opacity)
            result.opacity = 1
            return result
        }

        public static func contrast(_ a: Components, _ b: Components) -> Double {
            let (high, low) = a.luminance > b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
            return (high + 0.05) / (low + 0.05)
        }
    }

    public var light: Components
    public var dark: Components

    public init(light: Components, dark: Components) {
        self.light = light
        self.dark = dark
    }

    public init(light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1) {
        self.init(light: .init(hex: light, opacity: lightOpacity), dark: .init(hex: dark, opacity: darkOpacity))
    }

    public var color: Color {
        let light = light, dark = dark
        return Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
        })
    }
}

/// Color tokens, radii, and spacing from the Direction 1b handoff (`Design/openclaw-1b/README.md`).
/// The handoff's values are the dark variant; light values are tuned for a warm off-white base.
public struct AppTheme: Sendable {
    public var id: ThemeID
    public var bg: ThemeColor
    public var textPrimary: ThemeColor
    public var textSecondary: ThemeColor
    public var textTertiary: ThemeColor
    public var placeholder: ThemeColor
    public var accent: ThemeColor
    public var accentText: ThemeColor
    public var online: ThemeColor
    /// Amber for "Reconnecting…" (not in the handoff; added for connection status).
    public var warning: ThemeColor
    /// Destructive actions such as Disconnect (not in the handoff).
    public var danger: ThemeColor
    public var diffAdd: ThemeColor
    public var diffRemove: ThemeColor
    public var glowCoral: ThemeColor
    public var glowViolet: ThemeColor
    public var glowBlue: ThemeColor
    public var avatarStart: ThemeColor
    public var avatarEnd: ThemeColor
    /// The initial drawn on the avatar gradient; dark in both appearances because the gradient is light.
    public var textOnAvatar: Color { Color(red: 0.11, green: 0.105, blue: 0.12) }

    public static let coral = AppTheme(
        id: .coral,
        bg: .init(light: 0xF7F3EF, dark: 0x0B0B0F),
        textPrimary: .init(light: 0x1C1B1F, dark: 0xF5F5F7),
        // The handoff's white-at-opacity text, flattened onto each base as opaque values (slightly stronger than the
        // mock) so anti-aliased small text still measures above 4.5:1 in the accessibility audit.
        textSecondary: .init(light: 0x57534F, dark: 0xA8A8AD),
        textTertiary: .init(light: 0x67635F, dark: 0x8E8E93),
        placeholder: .init(light: 0x7A7672, dark: 0x76767B),
        accent: .init(light: 0xB24F2A, dark: 0xF28A5E),
        accentText: .init(light: 0x9A4120, dark: 0xF9A987),
        online: .init(light: 0x1E8C4E, dark: 0x5CD98A),
        warning: .init(light: 0x9A5B00, dark: 0xF2B33D),
        danger: .init(light: 0xB3261E, dark: 0xFF8A7A),
        diffAdd: .init(light: 0x1E7F45, dark: 0x7EE0A0),
        diffRemove: .init(light: 0xB3392B, dark: 0xF08A7A),
        glowCoral: .init(light: 0xF08A5E, lightOpacity: 0.30, dark: 0xE8613A, darkOpacity: 0.55),
        glowViolet: .init(light: 0xB494EC, lightOpacity: 0.24, dark: 0x9A6BE0, darkOpacity: 0.42),
        glowBlue: .init(light: 0x7BB8E0, lightOpacity: 0.16, dark: 0x3A8FC8, darkOpacity: 0.20),
        avatarStart: .init(light: 0xF8A66A, dark: 0xF8A66A),
        avatarEnd: .init(light: 0xE04E3A, dark: 0xE04E3A)
    )

    /// Corner radii from the handoff.
    public enum Radius {
        public static let promptCard: CGFloat = 30
        public static let card: CGFloat = 24
        public static let chatCard: CGFloat = 22
        public static let timelineCard: CGFloat = 20
        public static let codeBlock: CGFloat = 12
        public static let iconTile: CGFloat = 11
        public static let smallIconTile: CGFloat = 9
    }

    /// Layout spacing from the handoff.
    public enum Metrics {
        public static let homePadding: CGFloat = 20
        public static let screenPadding: CGFloat = 16
        public static let sectionSpacing: CGFloat = 26
        public static let cardSpacing: CGFloat = 10
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.coral
}

extension EnvironmentValues {
    /// The active theme. The app root sets it from `@AppStorage(ThemeID.storageKey)`.
    public var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
