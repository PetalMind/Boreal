import SwiftUI

struct BorealGlassBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private struct BorealSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08))
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func borealSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(BorealSurface(cornerRadius: cornerRadius))
    }
}
