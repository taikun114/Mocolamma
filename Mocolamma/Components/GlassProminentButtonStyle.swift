import SwiftUI

extension View {
    @ViewBuilder
    func applyGlassProminentButtonStyle(isDisabled: Bool) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if !isDisabled {
                self.buttonStyle(.glassProminent)
            } else {
                self
            }
        } else {
            self
        }
    }
}