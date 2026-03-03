import SwiftUI

extension View {
    @ViewBuilder
    func applyGlassProminentButtonStyle(isDisabled: Bool) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            if !isDisabled {
#if os(visionOS)
                self.buttonStyle(.borderedProminent)
#else
                self.buttonStyle(.glassProminent)
#endif
            } else {
                self
            }
        } else {
            self
        }
    }
}