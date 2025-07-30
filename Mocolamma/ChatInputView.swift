import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    @Binding var isStreaming: Bool // isSending を isStreaming に変更
    let selectedModel: OllamaModel?
    let sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil // 新しいクロージャを追加

    var body: some View {
        MessageInputView(inputText: $inputText, isStreaming: $isStreaming, selectedModel: selectedModel, sendMessage: sendMessage, stopMessage: stopMessage)
        
    }
}
