import SwiftUI

/// 操作の無効化は即時に反映し、見た目の透明度だけをフェードさせます。
struct DisabledStateFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isDisabled ? 0.5 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isDisabled)
            .disabled(isDisabled)
    }
}
