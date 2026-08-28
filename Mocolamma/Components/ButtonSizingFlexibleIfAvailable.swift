import SwiftUI

struct ButtonSizingFlexibleIfAvailable: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if #available(macOS 26.0, *) {
            content.buttonSizing(.flexible)
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
    /// macOS 26.0以降で利用可能な場合にフレキシブルなボタンサイジングを適用
    @ViewBuilder
    func buttonSizingFlexibleIfAvailable() -> some View {
        self.modifier(ButtonSizingFlexibleIfAvailable())
    }
}
