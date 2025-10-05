import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    @Binding var isStreaming: Bool // isSending を isStreaming に変更
    @Binding var showingInspector: Bool
    let selectedModel: OllamaModel?
    let sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil // 新しいクロージャを追加

    var body: some View {
        MessageInputView(inputText: $inputText, isStreaming: $isStreaming, showingInspector: $showingInspector, selectedModel: selectedModel, sendMessage: sendMessage, stopMessage: stopMessage)
        #if os(iOS)
            .gesture(
                DragGesture().onChanged { value in
                    if value.translation.height > 30 { // 30ポイント下にドラッグ
                        self.hideKeyboard()
                    }
                }
            )
        #endif
    }

    #if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif
}
