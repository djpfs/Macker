//===----------------------------------------------------------------------===//
// ThemedBackground — panel fills that follow the app's light/dark choice.
//
// `Color(nsColor:)` dynamic colors are resolved once and are not redrawn when
// only the AppKit appearance changes, so switching themes left white cards in
// dark mode. These fills read SwiftUI's `colorScheme`, which the theme
// switcher updates, so every switch redraws them.
//===----------------------------------------------------------------------===//

import SwiftUI

extension View {
    /// Card or chart fill (formerly `controlBackgroundColor`).
    func surfaceBackground(cornerRadius: CGFloat = 0) -> some View {
        modifier(ThemedBackground(role: .surface, cornerRadius: cornerRadius))
    }

    /// List, log, or terminal fill (formerly `textBackgroundColor`).
    func contentBackground() -> some View {
        modifier(ThemedBackground(role: .content, cornerRadius: 0))
    }
}

private struct ThemedBackground: ViewModifier {
    enum Role { case surface, content }

    let role: Role
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let fill = colorScheme == .dark ? darkFill : Color.white
        if cornerRadius > 0 {
            content.background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.background(fill)
        }
    }

    private var darkFill: Color {
        switch role {
        case .surface: Color(white: 0.16)
        case .content: Color(white: 0.12)
        }
    }
}
