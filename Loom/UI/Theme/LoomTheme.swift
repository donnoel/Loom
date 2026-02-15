import SwiftUI

nonisolated enum LoomTheme {
    private static let darkTextPrimary = Color(red: 0.91, green: 0.93, blue: 0.97)
    private static let darkTextSecondary = Color(red: 0.67, green: 0.71, blue: 0.78)
    private static let darkTextMuted = Color(red: 0.50, green: 0.54, blue: 0.64)
    private static let darkSurfaceBorder = Color.white.opacity(0.14)
    private static let darkFocusRing = Color(red: 0.37, green: 0.66, blue: 1.00)
    private static let darkActiveInputBorder = Color(red: 0.47, green: 0.65, blue: 1.00)

    private static let darkBackground = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.13, blue: 0.20).opacity(0.92),
            Color(red: 0.13, green: 0.19, blue: 0.30).opacity(0.88),
            Color(red: 0.07, green: 0.11, blue: 0.17).opacity(0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightBackground = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.99, blue: 1.00).opacity(0.96),
            Color(red: 0.93, green: 0.97, blue: 1.00).opacity(0.94),
            Color(red: 0.87, green: 0.93, blue: 0.99).opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAccent = LinearGradient(
        colors: [
            Color(red: 0.44, green: 0.62, blue: 0.92).opacity(0.76),
            Color(red: 0.33, green: 0.52, blue: 0.86).opacity(0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightAccent = LinearGradient(
        colors: [
            Color(red: 0.56, green: 0.72, blue: 0.95).opacity(0.64),
            Color(red: 0.46, green: 0.64, blue: 0.91).opacity(0.60)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkUserBubble = LinearGradient(
        colors: [
            Color(red: 0.43, green: 0.58, blue: 0.90).opacity(0.90),
            Color(red: 0.34, green: 0.50, blue: 0.84).opacity(0.88),
            Color(red: 0.27, green: 0.42, blue: 0.77).opacity(0.84)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightUserBubble = LinearGradient(
        colors: [
            Color(red: 0.76, green: 0.86, blue: 0.99).opacity(0.96),
            Color(red: 0.67, green: 0.80, blue: 0.97).opacity(0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAssistantBubble = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.25, blue: 0.34).opacity(0.92),
            Color(red: 0.16, green: 0.21, blue: 0.31).opacity(0.90)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightAssistantBubble = LinearGradient(
        colors: [
            Color.white.opacity(0.95),
            Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.94)
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

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextPrimary : .primary
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextSecondary : .secondary
    }

    static func textMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextMuted : Color.secondary.opacity(0.75)
    }

    static func surfaceBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceBorder : Color.primary.opacity(0.12)
    }

    static func focusRing(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkFocusRing : Color.accentColor.opacity(0.70)
    }

    static func activeInputBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkActiveInputBorder : Color.accentColor.opacity(0.72)
    }

    static func inputPlaceholder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.59, green: 0.64, blue: 0.73) : Color.secondary.opacity(0.72)
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
        .system(.title2, design: .default).weight(.semibold)
    }

    nonisolated enum Typography {
        static var pageTitle: Font { .title2.weight(.semibold) }
        static var pageHero: Font { .title3.weight(.semibold) }
        static var sectionTitle: Font { .headline }
        static var body: Font { .body }
        static var bodyStrong: Font { .subheadline.weight(.semibold) }
        static var bodyRegular: Font { .body }
        static var caption: Font { .caption }
        static var captionStrong: Font { .caption.weight(.semibold) }
        static var captionTiny: Font { .caption2 }
        static var captionTinyStrong: Font { .caption2.weight(.semibold) }
        static var footnote: Font { .footnote }
        static var footnoteStrong: Font { .footnote.weight(.semibold) }
        static var monospacedCaption: Font { .caption.monospaced() }
        static var monospacedBody: Font { .system(.body, design: .monospaced) }
        static var monospacedFootnote: Font { .system(.footnote, design: .monospaced) }
        static var chatBubbleChip: Font { .callout }
        static var chatBubbleBody: Font { .system(size: 14, weight: .regular, design: .default) }
    }

    static func bubblePalette(
        role: ChatMessage.Role,
        scheme: ColorScheme
    ) -> (
        alignment: Alignment,
        background: AnyShapeStyle,
        foreground: Color,
        stroke: Color,
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
                foreground: scheme == .dark ? .white : Color(red: 0.14, green: 0.23, blue: 0.39),
                stroke: scheme == .dark ? Color.white : Color.primary,
                strokeOpacity: scheme == .dark ? 0.30 : 0.18,
                cornerRadius: 20,
                shadow: Color.black.opacity(scheme == .dark ? 0.14 : 0.05),
                shadowRadius: scheme == .dark ? 8 : 5,
                shadowYOffset: scheme == .dark ? 2 : 1
            )

        case .assistant:
            return (
                alignment: .leading,
                background: scheme == .dark
                    ? AnyShapeStyle(Color.white.opacity(0.025))
                    : AnyShapeStyle(.ultraThinMaterial),
                foreground: textPrimary(scheme),
                stroke: scheme == .dark ? Color.white : Color.primary,
                strokeOpacity: scheme == .dark ? 0.16 : 0.14,
                cornerRadius: 20,
                shadow: Color.black.opacity(scheme == .dark ? 0.08 : 0.03),
                shadowRadius: scheme == .dark ? 5 : 3,
                shadowYOffset: 1
            )

        case .system, .tool:
            return (
                alignment: .leading,
                background: AnyShapeStyle(Color.secondary.opacity(scheme == .dark ? 0.18 : 0.12)),
                foreground: textSecondary(scheme),
                stroke: scheme == .dark ? Color.white : Color.primary,
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
        let bubbleMaxWidth: CGFloat = role == .user ? 420 : 760
        let bubbleShape = RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)

        content
            .foregroundStyle(palette.foreground)
            .font(isChipRole ? LoomTheme.Typography.chatBubbleChip : LoomTheme.Typography.chatBubbleBody)
            .lineSpacing(isChipRole ? 1 : 5)
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
            .padding(.horizontal, isChipRole ? 10 : 16)
            .padding(.vertical, isChipRole ? 6 : 11)
            .background {
                bubbleShape
                    .fill(palette.background)
                    .overlay {
                        bubbleShape
                            .strokeBorder(palette.stroke.opacity(palette.strokeOpacity), lineWidth: 1)
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
            .frame(maxWidth: bubbleMaxWidth, alignment: palette.alignment)
    }
}

private struct LoomSidebarItemModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let selected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let selectedStrokeOpacity = colorScheme == .dark ? 0.32 : 0.20
        let unselectedStrokeOpacity = colorScheme == .dark ? 0.12 : 0.07

        content
            .background {
                if selected {
                    if colorScheme == .dark {
                        shape
                            .fill(Color(red: 0.48, green: 0.34, blue: 0.66).opacity(0.70))
                            .overlay {
                                shape.fill(Color.white.opacity(0.06))
                            }
                            .overlay {
                                shape.strokeBorder(Color(red: 0.78, green: 0.61, blue: 1.00).opacity(0.40), lineWidth: 0.8)
                            }
                    } else {
                        shape
                            .fill(LoomTheme.accentGradient(colorScheme).opacity(0.20))
                            .overlay {
                                shape.fill(Color.white.opacity(0.34))
                            }
                            .overlay {
                                shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                            }
                    }
                } else {
                    shape
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.020))
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
                radius: 8,
                x: 0,
                y: 2
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
