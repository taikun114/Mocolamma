import SwiftUI

struct SoftEdgeIfAvailable: ViewModifier {
    var enabled: Bool = true
    
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

extension View {
    /// 利用可能な場合にソフトなスクロールエッジエフェクトを適用
    @ViewBuilder
    func adaptiveScrollEdgeEffect(enabled: Bool = true) -> some View {
        self.modifier(SoftEdgeIfAvailable(enabled: enabled))
    }
    
    /// 利用可能な場合にソフトなスクロールエッジエフェクトを適用
    @ViewBuilder
    func softEdgeIfAvailable(enabled: Bool = true) -> some View {
        self.modifier(SoftEdgeIfAvailable(enabled: enabled))
    }
}
