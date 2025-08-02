import SwiftUI

struct ChatMessagesView: View {
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    var body: some View {
        if #available(macOS 26, *) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in // messages.indices から messages に変更
                        // 最後のメッセージかどうかを判定
                        let isLastAssistantMessage = message.role == "assistant" && messages.last?.id == message.id
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
                    ForEach(messages) { message in // messages.indices から messages に変更
                        // 最後のメッセージかどうかを判定
                        let isLastAssistantMessage = message.role == "assistant" && messages.last?.id == message.id
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