import SwiftUI

/// The Muse-style ambient glow behind each screen. Softer in light mode; a flat base when Reduce Transparency is on.
public struct AmbientGlow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.bg.color
                if !reduceTransparency {
                    blob(theme.glowCoral.color)
                        .offset(x: -geometry.size.width * 0.35, y: -geometry.size.height * 0.33)
                    blob(theme.glowViolet.color)
                        .offset(x: geometry.size.width * 0.45, y: -geometry.size.height * 0.28)
                    blob(theme.glowBlue.color)
                        .offset(x: -geometry.size.width * 0.25, y: geometry.size.height * 0.2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: 220))
            .frame(width: 440, height: 440)
    }
}

extension View {
    /// Liquid Glass in `shape`. Use `interactive` for tappable glass.
    public func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }

    /// Section header styling (design 20 bold → `.title3.bold()`).
    public func sectionHeader() -> some View {
        font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.Metrics.sectionSpacing)
            .padding(.bottom, AppTheme.Metrics.cardSpacing)
            .padding(.horizontal, 2)
    }
}

/// Cards scale to 0.98 while pressed; no scaling with Reduce Motion.
public struct PressScale: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressScaleBody(configuration: configuration)
    }

    private struct PressScaleBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// A 4-point progress bar. Not used by the redesign yet; kept for future step progress.
public struct ProgressLine: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var value: Double

    public init(value: Double) { self.value = value }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.textPrimary.color.opacity(0.1))
                Capsule().fill(theme.accent.color)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .smooth, value: value)
        .accessibilityElement()
        .accessibilityValue(Text(min(max(value, 0), 1), format: .percent.precision(.fractionLength(0))))
    }
}

/// A gradient circle with the agent's initial, or a symbol when the agent name is unknown.
public struct AgentAvatar: View {
    @Environment(\.appTheme) private var theme
    @ScaledMetric private var size: CGFloat
    let name: String?

    public init(name: String?, size: CGFloat = 30) {
        self.name = name
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// The uppercased first letter or digit of `name`, or nil when there isn't one.
    nonisolated public static func initial(for name: String?) -> String? {
        guard let character = name?.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return String(character).uppercased()
    }

    public var body: some View {
        Circle()
            .fill(LinearGradient(colors: [theme.avatarStart.color, theme.avatarEnd.color],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Group {
                    if let initial = Self.initial(for: name) {
                        Text(initial).font(.system(size: size * 0.46, weight: .bold))
                    } else {
                        Image(systemName: "sparkles").font(.system(size: size * 0.42, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
