import SwiftUI

struct MessageInputView: View {
    @Binding var inputText: String
    @Binding var isSending: Bool
    var selectedModel: OllamaModel?
    var sendMessage: () -> Void

    var body: some View {
        HStack {
            TextField("Type your message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .disabled(isSending || selectedModel == nil)
                .lineLimit(1...10)
                .padding(.horizontal, 10) // テキストと枠線の間にスペースを追加
                .padding(.vertical, 8) // 上下の余白を追加
                .background(Color.gray.opacity(0.15)) // TextFieldの背景を透明にする
                .cornerRadius(16) // 角を丸くする
                .onKeyPress(KeyEquivalent.return) {
                    if NSEvent.modifierFlags.contains(.shift) {
                        inputText += "\n"
                        return .handled
                    } else {
                        sendMessage()
                        return .handled
                    }
                }

            if isSending {
                ProgressView()
            }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(inputText.isEmpty || isSending || selectedModel == nil ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isSending || selectedModel == nil)
        }
        .padding()
        .background(Color.clear)
    }
}
