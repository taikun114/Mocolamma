import SwiftUI

struct SoftEdgeIfAvailable: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26, *) {
            return enabled ? AnyView(content.scrollEdgeEffectStyle(.soft, for: .bottom)) : AnyView(content)
        } else {
            return AnyView(content)
        }
#else
        if #available(macOS 26, *) {
            return enabled ? AnyView(content.scrollEdgeEffectStyle(.soft, for: .bottom)) : AnyView(content)
        } else {
            return AnyView(content)
        }
#endif
    }
}
