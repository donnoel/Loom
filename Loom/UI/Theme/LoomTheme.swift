import SwiftUI

nonisolated enum LoomTheme {
    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.24),
                    Color(red: 0.06, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.95, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func accentGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.43, green: 0.64, blue: 0.92),
                    Color(red: 0.37, green: 0.48, blue: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.71, blue: 0.92),
                Color(red: 0.49, green: 0.60, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardBackground(in colorScheme: ColorScheme) -> some ShapeStyle {
        AnyShapeStyle(colorScheme == .dark ? .regularMaterial : .thinMaterial)
    }

    static func cardOverlayStroke() -> some ShapeStyle {
        AnyShapeStyle(Color.primary.opacity(0.12))
    }

    static func bubbleStyle(
        role: ChatMessage.Role,
        colorScheme: ColorScheme
    ) -> (alignment: HorizontalAlignment, bg: AnyShapeStyle, fg: Color) {
        if role == .user {
            let tint = accentGradient(for: colorScheme)
            let opacity = colorScheme == .dark ? 0.32 : 0.24
            return (
                alignment: .trailing,
                bg: AnyShapeStyle(tint.opacity(opacity)),
                fg: .primary
            )
        }

        return (
            alignment: .leading,
            bg: AnyShapeStyle(colorScheme == .dark ? .regularMaterial : .ultraThinMaterial),
            fg: .primary
        )
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
                    .fill(LoomTheme.cardBackground(in: colorScheme))
                    .overlay {
                        shape.strokeBorder(LoomTheme.cardOverlayStroke(), lineWidth: 0.8)
                    }
            }
    }
}

private struct LoomBubbleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let role: ChatMessage.Role

    func body(content: Content) -> some View {
        let style = LoomTheme.bubbleStyle(role: role, colorScheme: colorScheme)

        content
            .foregroundStyle(style.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.bg)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LoomTheme.cardOverlayStroke(), lineWidth: 0.7)
                    }
            }
            .frame(maxWidth: 620, alignment: style.alignment == .trailing ? .trailing : .leading)
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
