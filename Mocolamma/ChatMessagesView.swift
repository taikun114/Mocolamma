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
                        let isLastOwnUserMessage = message.role == "user" && messages.last(where: { $0.role == "user" })?.id == message.id
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, isLastOwnUserMessage: isLastOwnUserMessage, onRetry: onRetry, isStreamingAny: messages.contains { $0.role == "assistant" && $0.isStreaming })
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
                        let isLastOwnUserMessage = message.role == "user" && messages.last(where: { $0.role == "user" })?.id == message.id
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, isLastOwnUserMessage: isLastOwnUserMessage, onRetry: onRetry, isStreamingAny: messages.contains { $0.role == "assistant" && $0.isStreaming })
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 50) // Height of the bottom overlay
            }
        }
    }
}