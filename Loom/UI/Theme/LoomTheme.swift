import SwiftUI

nonisolated enum LoomTheme {
    private static let darkBackground = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.32),
            Color(red: 0.34, green: 0.47, blue: 0.72).opacity(0.24),
            Color(red: 0.10, green: 0.13, blue: 0.20).opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightBackground = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.20),
            Color(red: 0.62, green: 0.74, blue: 0.90).opacity(0.16),
            Color(red: 0.94, green: 0.97, blue: 1.00).opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAccent = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.72),
            Color(red: 0.42, green: 0.56, blue: 0.86).opacity(0.68)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightAccent = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.62),
            Color(red: 0.56, green: 0.69, blue: 0.90).opacity(0.58)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func backgroundGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark ? darkBackground : lightBackground
    }

    static func accentGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark ? darkAccent : lightAccent
    }

    // Backward-compatible label form used in a few existing call sites.
    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        backgroundGradient(scheme)
    }

    // Backward-compatible label form used in a few existing call sites.
    static func accentGradient(for scheme: ColorScheme) -> LinearGradient {
        accentGradient(scheme)
    }

    static func sessionHeaderFont() -> Font {
        .system(.title, design: .default).weight(.semibold)
    }

    static func bubblePalette(
        role: ChatMessage.Role,
        scheme: ColorScheme
    ) -> (alignment: Alignment, background: AnyShapeStyle, foreground: Color, strokeOpacity: Double, cornerRadius: CGFloat) {
        switch role {
        case .user:
            return (
                alignment: .trailing,
                background: AnyShapeStyle(accentGradient(scheme).opacity(scheme == .dark ? 0.86 : 0.78)),
                foreground: .white,
                strokeOpacity: scheme == .dark ? 0.38 : 0.30,
                cornerRadius: 15
            )

        case .assistant:
            return (
                alignment: .leading,
                background: AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.18 : 0.10)),
                foreground: .primary,
                strokeOpacity: scheme == .dark ? 0.30 : 0.22,
                cornerRadius: 15
            )

        case .system, .tool:
            return (
                alignment: .leading,
                background: AnyShapeStyle(Color.secondary.opacity(scheme == .dark ? 0.18 : 0.12)),
                foreground: .secondary,
                strokeOpacity: scheme == .dark ? 0.18 : 0.14,
                cornerRadius: 12
            )
        }
    }
}

private struct LoomCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

                shape
                    .fill(colorScheme == .dark ? .thinMaterial : .ultraThinMaterial)
                    .overlay {
                        shape.fill(LoomTheme.accentGradient(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07))
                    }
                    .overlay {
                        shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
                    }
            }
    }
}

private struct LoomBubbleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let role: ChatMessage.Role

    func body(content: Content) -> some View {
        let palette = LoomTheme.bubblePalette(role: role, scheme: colorScheme)
        let isChipRole = role == .system || role == .tool

        content
            .foregroundStyle(palette.foreground)
            .font(isChipRole ? .callout : .body)
            .lineSpacing(isChipRole ? 1 : 2)
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
            .padding(.horizontal, isChipRole ? 10 : 12)
            .padding(.vertical, isChipRole ? 6 : 10)
            .background {
                RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                    .fill(palette.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(palette.strokeOpacity), lineWidth: 1)
                    }
            }
            .frame(maxWidth: 680, alignment: palette.alignment)
    }
}

extension View {
    func loomCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(LoomCardModifier(cornerRadius: cornerRadius))
    }

    func loomBubble(role: ChatMessage.Role) -> some View {
        modifier(LoomBubbleModifier(role: role))
    }
}
