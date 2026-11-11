import SwiftUI

struct CopyFeedbackIcon: View {
    let isCopied: Bool
    var symbolName = SFSymbol.copy

    var body: some View {
        ZStack {
            Image(systemName: symbolName)
                .hidden()
            Image(systemName: "checkmark")
                .hidden()
            Image(systemName: isCopied ? "checkmark" : symbolName)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityHidden(true)
    }
}
