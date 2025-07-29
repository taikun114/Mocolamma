import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    @Binding var isSending: Bool
    let selectedModel: OllamaModel?
    let sendMessage: () -> Void

    var body: some View {
        MessageInputView(inputText: $inputText, isSending: $isSending, selectedModel: selectedModel) {
            sendMessage()
        }
        
    }
}
