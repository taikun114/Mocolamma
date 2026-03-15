import SwiftUI

struct SoftEdgeIfAvailable: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
#if os(macOS) || os(iOS)
        if #available(iOS 26, macOS 26, *) {
            return enabled ? AnyView(content.scrollEdgeEffectStyle(.soft, for: .all)) : AnyView(content)
        }
#endif
        return AnyView(content)
    }
}
