import SwiftUI

/// 判定画面の入力欄に共通の背景と、コントラスト設定に応じた枠線を適用します。
struct DecisionInputStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    var isInvalid = false

    func body(content: Content) -> some View {
        content
            .background(isEnabled ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isInvalid ? Color.red : (contrast == .increased ? (isEnabled ? Color.primary : Color.secondary) : .clear), lineWidth: isInvalid ? 2 : 1)
            }
    }
}
