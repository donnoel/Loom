import SwiftUI

nonisolated enum LoomTheme {
    private static let darkTextPrimary = Color(red: 0.94, green: 0.94, blue: 0.95)
    private static let darkTextSecondary = Color(red: 0.67, green: 0.71, blue: 0.78)
    private static let darkTextMuted = Color(red: 0.50, green: 0.54, blue: 0.64)
    private static let darkSurfaceBorder = Color.white.opacity(0.10)
    private static let darkFocusRing = Color(red: 0.37, green: 0.66, blue: 1.00)
    private static let darkActiveInputBorder = Color(red: 0.47, green: 0.65, blue: 1.00)

    private static let darkBackground = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.10, blue: 0.11),
            Color(red: 0.11, green: 0.11, blue: 0.12),
            Color(red: 0.10, green: 0.10, blue: 0.11)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightBackground = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.96, blue: 0.97),
            Color(red: 0.95, green: 0.95, blue: 0.96),
            Color(red: 0.94, green: 0.94, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAccent = LinearGradient(
        colors: [
            Color(red: 0.40, green: 0.24, blue: 0.64).opacity(0.88),
            Color(red: 0.32, green: 0.20, blue: 0.56).opacity(0.86)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightAccent = LinearGradient(
        colors: [
            Color(red: 0.53, green: 0.39, blue: 0.81).opacity(0.84),
            Color(red: 0.44, green: 0.31, blue: 0.75).opacity(0.80)
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

    static func sidebarSelectedText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkFocusRing : Color.accentColor
    }

    static func surfaceBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceBorder : Color.primary.opacity(0.09)
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
        static var chatBubbleBody: Font { .system(size: 15, weight: .regular, design: .default) }
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
                background: AnyShapeStyle(
                    Color(
                        red: scheme == .dark ? 0.34 : 0.42,
                        green: scheme == .dark ? 0.22 : 0.28,
                        blue: scheme == .dark ? 0.52 : 0.64
                    )
                ),
                foreground: .white,
                stroke: .clear,
                strokeOpacity: 0,
                cornerRadius: 18,
                shadow: Color.black.opacity(scheme == .dark ? 0.10 : 0.05),
                shadowRadius: scheme == .dark ? 4 : 2,
                shadowYOffset: 1
            )

        case .assistant:
            return (
                alignment: .leading,
                background: AnyShapeStyle(Color.clear),
                foreground: textPrimary(scheme),
                stroke: .clear,
                strokeOpacity: 0,
                cornerRadius: 0,
                shadow: .clear,
                shadowRadius: 0,
                shadowYOffset: 0
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
                    .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                    .overlay {
                        shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
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
        let isAssistantPlain = role == .assistant
        let bubbleMaxWidth: CGFloat = role == .user ? 430 : 720
        let bubbleShape = RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)

        content
            .foregroundStyle(palette.foreground)
            .font(isChipRole ? LoomTheme.Typography.chatBubbleChip : LoomTheme.Typography.chatBubbleBody)
            .lineSpacing(isChipRole ? 1 : 4)
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: max(palette.cornerRadius, 10), style: .continuous))
            .padding(.horizontal, isChipRole ? 10 : (isAssistantPlain ? 0 : 16))
            .padding(.vertical, isChipRole ? 6 : (isAssistantPlain ? 0 : 11))
            .background {
                if !isAssistantPlain {
                    bubbleShape
                        .fill(palette.background)
                        .overlay {
                            bubbleShape
                                .strokeBorder(palette.stroke.opacity(palette.strokeOpacity), lineWidth: 1)
                        }
                        .overlay {
                            bubbleShape
                                .strokeBorder(
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.36),
                                    lineWidth: role == .system || role == .tool ? 0 : 0.6
                                )
                        }
                }
            }
            .shadow(color: palette.shadow, radius: palette.shadowRadius, x: 0, y: palette.shadowYOffset)
            .frame(maxWidth: bubbleMaxWidth, alignment: palette.alignment)
    }
}

private struct LoomSidebarItemModifier: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
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
