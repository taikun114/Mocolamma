import SwiftUI

struct ChatMessagesView: View {
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID) -> Void)? // 新しいプロパティ: [ChatMessage]
    var body: some View {
        if #available(macOS 26, *) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages.indices, id: \.self) { index in
                        let message = messages[index]
                        // 最後のメッセージかどうかを判定
                        let isLastAssistantMessage = message.role == "assistant" && index == messages.count - 1
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, onRetry: onRetry)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 50) // Height of the bottom overlay
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)

        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages.indices, id: \.self) { index in
                        let message = messages[index]
                        // 最後のメッセージかどうかを判定
                        let isLastAssistantMessage = message.role == "assistant" && index == messages.count - 1
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, onRetry: onRetry)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 50) // Height of the bottom overlay
            }
        }
    }
}
