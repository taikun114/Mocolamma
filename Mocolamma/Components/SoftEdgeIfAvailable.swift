import SwiftUI

struct SoftEdgeIfAvailable: ViewModifier {
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS) || os(iOS)
        if #available(iOS 26, macOS 26, *) {
            if enabled {
                content.scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}
