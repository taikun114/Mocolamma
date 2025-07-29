import SwiftUI

struct MessageInputView: View {
    @Binding var inputText: String
    @Binding var isSending: Bool
    var selectedModel: OllamaModel?
    var sendMessage: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            ZStack(alignment: .leading) {
                if #available(macOS 26, *) {
                    Color.clear
                        .glassEffect(in: .rect(cornerRadius: 16.0))
                } else {
                    VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                        .cornerRadius(16)
                }
                TextField("Type your message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .disabled(selectedModel == nil)
                    .lineLimit(1...10)
                    .fixedSize(horizontal: false, vertical: true) // 高さをコンテンツに合わせる
                    .padding(.horizontal, 10) // テキストと枠線の間にスペースを追加
                    .padding(.vertical, 8) // 上下の余白を追加
                    .background(Color.clear) // TextFieldの背景を透明にする
                    .cornerRadius(16) // 角を丸くする
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1) // 枠線を追加
                    )
                    .onKeyPress(KeyEquivalent.return) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            inputText += "\n"
                            return .handled
                        } else if isSending {
                            return .handled // 送信中はEnterキーを無効化
                        } else {
                            sendMessage()
                            return .handled
                        }
                    }
            }
            .fixedSize(horizontal: false, vertical: true)

            if #available(macOS 26, *) {
                Button(action: sendMessage) {
                    ZStack {
                        Image(systemName: "arrow.up")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(7)
                            .glassEffect(.regular.tint(.accentColor).interactive())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isSending || selectedModel == nil)
            } else {
                Button(action: sendMessage) {
                    ZStack {
                        Image(systemName: "arrow.up")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Circle().fill(Color.accentColor))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isSending || selectedModel == nil)
            }

        }
        .padding()
        .background(Color.clear)
    }
}
