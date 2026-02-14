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

    private static let darkUserBubble = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.90),
            Color(red: 0.39, green: 0.53, blue: 0.86).opacity(0.88),
            Color(red: 0.25, green: 0.36, blue: 0.73).opacity(0.84)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightUserBubble = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.82),
            Color(red: 0.64, green: 0.76, blue: 0.94).opacity(0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAssistantBubble = LinearGradient(
        colors: [
            Color(red: 0.22, green: 0.25, blue: 0.34).opacity(0.92),
            Color(red: 0.17, green: 0.20, blue: 0.30).opacity(0.90)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightAssistantBubble = LinearGradient(
        colors: [
            Color.white.opacity(0.92),
            Color(red: 0.93, green: 0.96, blue: 0.99).opacity(0.90)
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
    ) -> (
        alignment: Alignment,
        background: AnyShapeStyle,
        foreground: Color,
        strokeOpacity: Double,
        cornerRadius: CGFloat,
        shadow: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) {
        switch role {
        case .user:
            return (
                alignment: .trailing,
                background: AnyShapeStyle(scheme == .dark ? darkUserBubble : lightUserBubble),
                foreground: .white,
                strokeOpacity: scheme == .dark ? 0.44 : 0.34,
                cornerRadius: 17,
                shadow: Color.black.opacity(scheme == .dark ? 0.28 : 0.10),
                shadowRadius: scheme == .dark ? 14 : 9,
                shadowYOffset: scheme == .dark ? 5 : 3
            )

        case .assistant:
            return (
                alignment: .leading,
                background: AnyShapeStyle(scheme == .dark ? darkAssistantBubble : lightAssistantBubble),
                foreground: .primary,
                strokeOpacity: scheme == .dark ? 0.34 : 0.22,
                cornerRadius: 17,
                shadow: Color.black.opacity(scheme == .dark ? 0.20 : 0.06),
                shadowRadius: scheme == .dark ? 10 : 6,
                shadowYOffset: scheme == .dark ? 3 : 2
            )

        case .system, .tool:
            return (
                alignment: .leading,
                background: AnyShapeStyle(Color.secondary.opacity(scheme == .dark ? 0.18 : 0.12)),
                foreground: .secondary,
                strokeOpacity: scheme == .dark ? 0.18 : 0.14,
                cornerRadius: 12,
                shadow: .clear,
                shadowRadius: 0,
                shadowYOffset: 0
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
        let bubbleShape = RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)

        content
            .foregroundStyle(palette.foreground)
            .font(isChipRole ? .callout : .body)
            .lineSpacing(isChipRole ? 1 : 2)
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
            .padding(.horizontal, isChipRole ? 10 : 12)
            .padding(.vertical, isChipRole ? 6 : 10)
            .background {
                bubbleShape
                    .fill(palette.background)
                    .overlay {
                        bubbleShape
                            .strokeBorder(Color.primary.opacity(palette.strokeOpacity), lineWidth: 1)
                    }
                    .overlay {
                        bubbleShape
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40),
                                lineWidth: role == .system || role == .tool ? 0 : 0.6
                            )
                    }
            }
            .shadow(color: palette.shadow, radius: palette.shadowRadius, x: 0, y: palette.shadowYOffset)
            .frame(maxWidth: 680, alignment: palette.alignment)
    }
}

private struct LoomSidebarItemModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let selected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let selectedStrokeOpacity = colorScheme == .dark ? 0.28 : 0.16
        let unselectedStrokeOpacity = colorScheme == .dark ? 0.12 : 0.08

        content
            .background {
                if selected {
                    shape
                        .fill(LoomTheme.accentGradient(colorScheme).opacity(colorScheme == .dark ? 0.30 : 0.16))
                        .overlay {
                            shape.fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.30))
                        }
                } else {
                    shape
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
                }
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(selected ? selectedStrokeOpacity : unselectedStrokeOpacity),
                    lineWidth: 1
                )
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule(style: .continuous)
                        .fill(LoomTheme.accentGradient(colorScheme))
                        .frame(width: 4)
                        .padding(.vertical, 5)
                        .padding(.leading, 4)
                }
            }
            .shadow(
                color: selected ? Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10) : .clear,
                radius: 10,
                x: 0,
                y: 3
            )
    }
}

extension View {
    func loomCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(LoomCardModifier(cornerRadius: cornerRadius))
    }

    func loomBubble(role: ChatMessage.Role) -> some View {
        modifier(LoomBubbleModifier(role: role))
    }

    func loomSidebarItem(selected: Bool) -> some View {
        modifier(LoomSidebarItemModifier(selected: selected))
    }
}
