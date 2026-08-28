import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    @Binding var selectedImages: [ChatInputImage]
    @Binding var selectedAttachments: [ChatInputAttachment]
    @Binding var isStreaming: Bool
    @Binding var showingInspector: Bool
    var placeholder: String = "Type your message..."
    let selectedModel: OllamaModel?
    let sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil
    
    init(
        inputText: Binding<String>,
        selectedImages: Binding<[ChatInputImage]>,
        selectedAttachments: Binding<[ChatInputAttachment]> = .constant([]),
        isStreaming: Binding<Bool>,
        showingInspector: Binding<Bool>,
        placeholder: String = "Type your message...",
        selectedModel: OllamaModel?,
        sendMessage: @escaping () -> Void,
        stopMessage: (() -> Void)? = nil
    ) {
        self._inputText = inputText
        self._selectedImages = selectedImages
        self._selectedAttachments = selectedAttachments
        self._isStreaming = isStreaming
        self._showingInspector = showingInspector
        self.placeholder = placeholder
        self.selectedModel = selectedModel
        self.sendMessage = sendMessage
        self.stopMessage = stopMessage
    }
    
    var body: some View {
        MessageInputView(
            inputText: $inputText,
            selectedImages: $selectedImages,
            selectedAttachments: $selectedAttachments,
            isStreaming: $isStreaming,
            showingInspector: $showingInspector,
            placeholder: placeholder,
            selectedModel: selectedModel,
            sendMessage: sendMessage,
            stopMessage: stopMessage
        )
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
