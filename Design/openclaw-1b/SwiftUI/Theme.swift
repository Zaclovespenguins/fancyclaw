import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0B0B0F)
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary = Color.white.opacity(0.45)
    static let placeholder = Color.white.opacity(0.40)
    static let accent = Color(hex: 0xF28A5E)
    static let accentText = Color(hex: 0xF9A987)
    static let online = Color(hex: 0x5CD98A)
    static let diffAdd = Color(hex: 0x7EE0A0)
    static let diffRemove = Color(hex: 0xF08A7A)
    static let glowCoral = Color(hex: 0xE8613A)
    static let glowViolet = Color(hex: 0x9A6BE0)
    static let glowBlue = Color(hex: 0x3A8FC8)
    static let avatarGradient = LinearGradient(
        colors: [Color(hex: 0xF8A66A), Color(hex: 0xE04E3A)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Muse-style ambient glow behind every screen.
struct AmbientGlow: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg
                blob(Theme.glowCoral.opacity(0.55)).offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.33)
                blob(Theme.glowViolet.opacity(0.42)).offset(x: geo.size.width * 0.45, y: -geo.size.height * 0.28)
                blob(Theme.glowBlue.opacity(0.20)).offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.2)
            }
        }
        .ignoresSafeArea()
    }
    private func blob(_ c: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c, .clear], center: .center, startRadius: 0, endRadius: 220))
            .frame(width: 440, height: 440)
    }
}

extension View {
    /// Liquid Glass on iOS 26, material fallback before.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            var g: Glass = .regular
            if let tint { g = g.tint(tint) }
            if interactive { g = g.interactive() }
            return AnyView(self.glassEffect(g, in: shape))
        } else {
            return AnyView(self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.5)))
        }
    }

    func sectionHeader() -> some View {
        self.font(.system(size: 20, weight: .bold)).kerning(-0.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26).padding(.bottom, 10).padding(.horizontal, 2)
    }
}

struct AgentAvatar: View {
    var size: CGFloat = 30
    var body: some View {
        Circle().fill(Theme.avatarGradient)
            .frame(width: size, height: size)
            .overlay(Text("C").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white))
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ProgressLine: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Theme.accent).frame(width: g.size.width * value)
            }
        }
        .frame(height: 4)
        .animation(.smooth, value: value)
    }
}
