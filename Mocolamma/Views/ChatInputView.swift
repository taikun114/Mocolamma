import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    @Binding var selectedImages: [ChatInputImage]
    @Binding var isStreaming: Bool
    @Binding var showingInspector: Bool
    var placeholder: String = "Type your message..."
    let selectedModel: OllamaModel?
    let sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil
    
    var body: some View {
        MessageInputView(inputText: $inputText, selectedImages: $selectedImages, isStreaming: $isStreaming, showingInspector: $showingInspector, placeholder: placeholder, selectedModel: selectedModel, sendMessage: sendMessage, stopMessage: stopMessage)
#if !os(macOS)
            .gesture(
                DragGesture().onChanged { value in
                    if value.translation.height > 30 { // 30ポイント下にドラッグ
                        self.hideKeyboard()
                    }
                }
            )
#endif
    }
    
#if !os(macOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
#endif
}
