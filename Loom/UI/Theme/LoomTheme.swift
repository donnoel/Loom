import SwiftUI

nonisolated enum LoomTheme {
    static let coral = Color(red: 1.00, green: 0.31, blue: 0.43)
    static let saffron = Color(red: 1.00, green: 0.72, blue: 0.20)
    static let aqua = Color(red: 0.16, green: 0.86, blue: 0.84)
    static let ultraviolet = Color(red: 0.47, green: 0.35, blue: 1.00)

    private static let darkTextPrimary = Color(red: 0.97, green: 0.96, blue: 1.00)
    private static let darkTextSecondary = Color(red: 0.76, green: 0.78, blue: 0.88)
    private static let darkTextMuted = Color(red: 0.55, green: 0.58, blue: 0.70)
    private static let darkSurfaceBorder = Color(red: 0.56, green: 0.50, blue: 1.00).opacity(0.28)
    private static let darkFocusRing = aqua
    private static let darkActiveInputBorder = coral

    private static let darkBackground = LinearGradient(
        colors: [
            Color(red: 0.035, green: 0.025, blue: 0.10),
            Color(red: 0.075, green: 0.035, blue: 0.13),
            Color(red: 0.02, green: 0.09, blue: 0.13)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let lightBackground = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.96, blue: 0.88),
            Color(red: 0.98, green: 0.93, blue: 0.98),
            Color(red: 0.89, green: 0.98, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let darkAccent = LinearGradient(
        colors: [
            coral,
            Color(red: 1.00, green: 0.45, blue: 0.32),
            saffron
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private static let lightAccent = LinearGradient(
        colors: [
            Color(red: 0.92, green: 0.16, blue: 0.34),
            Color(red: 0.98, green: 0.38, blue: 0.18),
            Color(red: 0.93, green: 0.60, blue: 0.05)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    nonisolated enum Flavor {
        case sunset
        case tide
        case ultraviolet
    }

    static func backgroundGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark ? darkBackground : lightBackground
    }

    static func accentGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark ? darkAccent : lightAccent
    }

    static func tintColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? saffron : Color(red: 0.63, green: 0.16, blue: 0.55)
    }

    static func sidebarBackground(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.055, green: 0.035, blue: 0.13), Color(red: 0.025, green: 0.08, blue: 0.12)]
                : [Color(red: 1.00, green: 0.93, blue: 0.84), Color(red: 0.91, green: 0.97, blue: 0.97)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardWash(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [ultraviolet.opacity(0.13), aqua.opacity(0.07), coral.opacity(0.05)]
                : [Color.white.opacity(0.70), ultraviolet.opacity(0.055), aqua.opacity(0.075)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func neutralCardFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [
                    Color(red: 0.075, green: 0.065, blue: 0.13).opacity(0.92),
                    Color(red: 0.045, green: 0.09, blue: 0.12).opacity(0.90)
                ]
                : [
                    Color.white.opacity(0.86),
                    Color(red: 0.97, green: 0.98, blue: 0.99).opacity(0.82)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func neutralCardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    static func chromaticBorder(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [coral, saffron, aqua, ultraviolet, coral].map {
                $0.opacity(scheme == .dark ? 0.52 : 0.38)
            },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func selectionGradient(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [coral.opacity(0.22), ultraviolet.opacity(0.24), aqua.opacity(0.14)]
                : [coral.opacity(0.16), saffron.opacity(0.18), aqua.opacity(0.16)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func composerFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.10, green: 0.055, blue: 0.18), Color(red: 0.035, green: 0.13, blue: 0.16)]
                : [Color.white.opacity(0.92), Color(red: 0.94, green: 0.98, blue: 0.96)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func controlFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [ultraviolet.opacity(0.22), aqua.opacity(0.13)]
                : [ultraviolet.opacity(0.10), aqua.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func featureGradient(_ flavor: Flavor, scheme: ColorScheme) -> LinearGradient {
        let opacity = scheme == .dark ? 0.34 : 0.22
        let colors: [Color]
        switch flavor {
        case .sunset:
            colors = [coral.opacity(opacity), saffron.opacity(opacity * 0.85), ultraviolet.opacity(opacity * 0.55)]
        case .tide:
            colors = [aqua.opacity(opacity), ultraviolet.opacity(opacity * 0.75), coral.opacity(opacity * 0.45)]
        case .ultraviolet:
            colors = [ultraviolet.opacity(opacity), coral.opacity(opacity * 0.78), aqua.opacity(opacity * 0.55)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
        scheme == .dark ? Color.white : Color(red: 0.50, green: 0.07, blue: 0.38)
    }

    static func surfaceBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceBorder : Color.primary.opacity(0.09)
    }

    static func focusRing(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkFocusRing : ultraviolet.opacity(0.72)
    }

    static func activeInputBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkActiveInputBorder : coral.opacity(0.72)
    }

    static func inputPlaceholder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.66, green: 0.71, blue: 0.82) : Color(red: 0.36, green: 0.31, blue: 0.43).opacity(0.72)
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
        .system(.title2, design: .rounded).weight(.bold)
    }

    nonisolated enum Typography {
        static var pageTitle: Font { .system(.title2, design: .rounded).weight(.bold) }
        static var pageHero: Font { .system(.title2, design: .rounded).weight(.bold) }
        static var sectionTitle: Font { .system(.headline, design: .rounded).weight(.semibold) }
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
                background: AnyShapeStyle(accentGradient(scheme)),
                foreground: .white,
                stroke: Color.white,
                strokeOpacity: scheme == .dark ? 0.20 : 0.32,
                cornerRadius: 20,
                shadow: coral.opacity(scheme == .dark ? 0.22 : 0.12),
                shadowRadius: scheme == .dark ? 10 : 6,
                shadowYOffset: 3
            )

        case .assistant:
            return (
                alignment: .leading,
                background: AnyShapeStyle(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [aqua.opacity(0.13), ultraviolet.opacity(0.16)]
                            : [Color.white.opacity(0.78), aqua.opacity(0.10), ultraviolet.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ),
                foreground: textPrimary(scheme),
                stroke: aqua,
                strokeOpacity: scheme == .dark ? 0.30 : 0.24,
                cornerRadius: 17,
                shadow: ultraviolet.opacity(scheme == .dark ? 0.16 : 0.08),
                shadowRadius: 8,
                shadowYOffset: 3
            )

        case .system, .tool:
            return (
                alignment: .leading,
                background: AnyShapeStyle(
                    LinearGradient(
                        colors: [saffron.opacity(scheme == .dark ? 0.18 : 0.16), coral.opacity(scheme == .dark ? 0.10 : 0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                ),
                foreground: textSecondary(scheme),
                stroke: saffron,
                strokeOpacity: scheme == .dark ? 0.30 : 0.26,
                cornerRadius: 12,
                shadow: .clear,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        }
    }
}

struct LoomBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LoomTheme.backgroundGradient(colorScheme)

                Circle()
                    .fill(LoomTheme.coral.opacity(colorScheme == .dark ? 0.20 : 0.16))
                    .frame(width: proxy.size.width * 0.52)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.34, y: -proxy.size.height * 0.34)

                Circle()
                    .fill(LoomTheme.aqua.opacity(colorScheme == .dark ? 0.18 : 0.15))
                    .frame(width: proxy.size.width * 0.50)
                    .blur(radius: 100)
                    .offset(x: proxy.size.width * 0.34, y: proxy.size.height * 0.30)

                RoundedRectangle(cornerRadius: 80, style: .continuous)
                    .fill(LoomTheme.ultraviolet.opacity(colorScheme == .dark ? 0.11 : 0.08))
                    .frame(width: proxy.size.width * 0.92, height: 72)
                    .rotationEffect(.degrees(-13))
                    .blur(radius: 24)
                    .offset(y: -proxy.size.height * 0.12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    .fill(.regularMaterial)
                    .overlay {
                        shape.fill(LoomTheme.neutralCardFill(colorScheme))
                    }
                    .overlay {
                        shape.strokeBorder(LoomTheme.neutralCardBorder(colorScheme), lineWidth: 1)
                    }
            }
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LoomTheme.chromaticBorder(colorScheme))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                    .padding(.leading, 1)
                    .accessibilityHidden(true)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}

private struct LoomFeatureCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let flavor: LoomTheme.Flavor
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .fill(.thinMaterial)
                    .overlay {
                        shape.fill(LoomTheme.featureGradient(flavor, scheme: colorScheme))
                    }
                    .overlay {
                        shape.strokeBorder(LoomTheme.chromaticBorder(colorScheme), lineWidth: 1.25)
                    }
            }
            .shadow(
                color: LoomTheme.coral.opacity(colorScheme == .dark ? 0.15 : 0.09),
                radius: 18,
                x: 0,
                y: 7
            )
    }
}

private struct LoomBubbleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let role: ChatMessage.Role

    func body(content: Content) -> some View {
        let palette = LoomTheme.bubblePalette(role: role, scheme: colorScheme)
        let isChipRole = role == .system || role == .tool
        let bubbleMaxWidth: CGFloat = role == .user ? 430 : 720
        let bubbleShape = RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)

        content
            .foregroundStyle(palette.foreground)
            .font(isChipRole ? LoomTheme.Typography.chatBubbleChip : LoomTheme.Typography.chatBubbleBody)
            .lineSpacing(isChipRole ? 1 : 4)
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: max(palette.cornerRadius, 10), style: .continuous))
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
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.36),
                                lineWidth: role == .system || role == .tool ? 0 : 0.6
                            )
                    }
            }
            .overlay(alignment: .leading) {
                if role == .assistant {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [LoomTheme.aqua, LoomTheme.ultraviolet, LoomTheme.coral],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 9)
                        .padding(.leading, 5)
                        .accessibilityHidden(true)
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
        content
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LoomTheme.selectionGradient(colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(LoomTheme.chromaticBorder(colorScheme), lineWidth: 0.75)
                        }
                }
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule(style: .continuous)
                        .fill(LoomTheme.accentGradient(colorScheme))
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func loomCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(LoomCardModifier(cornerRadius: cornerRadius))
    }

    func loomFeatureCard(_ flavor: LoomTheme.Flavor, cornerRadius: CGFloat = 16) -> some View {
        modifier(LoomFeatureCardModifier(flavor: flavor, cornerRadius: cornerRadius))
    }

    func loomBubble(role: ChatMessage.Role) -> some View {
        modifier(LoomBubbleModifier(role: role))
    }

    func loomSidebarItem(selected: Bool) -> some View {
        modifier(LoomSidebarItemModifier(selected: selected))
    }
}
