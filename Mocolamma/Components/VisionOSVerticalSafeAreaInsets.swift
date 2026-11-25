import SwiftUI

#if os(visionOS)
extension View {
    func visionOSVerticalSafeAreaInsets() -> some View {
        let inset: CGFloat = 8
        return self
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: inset)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: inset)
            }
    }
}
#endif
