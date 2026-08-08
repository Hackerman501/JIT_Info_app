import SwiftUI

struct GlassCardModifier: ViewModifier {
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if liquidGlassEnabled {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                content.background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
