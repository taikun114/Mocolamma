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
                        let pairedAssistantStreaming: Bool = {
                            if message.role == "user" {
                                if let startIdx = messages.firstIndex(where: { $0.id == message.id }) {
                                    if let assistantIdx = messages[startIdx...].firstIndex(where: { $0.role == "assistant" }) {
                                        return messages[assistantIdx].isStreaming
                                    } else {
                                        if let last = messages.last, last.role == "assistant" {
                                            return last.isStreaming
                                        }
                                    }
                                }
                            }
                            return false
                        }()
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, isLastOwnUserMessage: isLastOwnUserMessage, onRetry: onRetry, isStreamingAny: pairedAssistantStreaming, allMessages: $messages)
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
                        let pairedAssistantStreaming: Bool = {
                            if message.role == "user" {
                                if let startIdx = messages.firstIndex(where: { $0.id == message.id }) {
                                    if let assistantIdx = messages[startIdx...].firstIndex(where: { $0.role == "assistant" }) {
                                        return messages[assistantIdx].isStreaming
                                    } else {
                                        if let last = messages.last, last.role == "assistant" {
                                            return last.isStreaming
                                        }
                                    }
                                }
                            }
                            return false
                        }()
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, isLastOwnUserMessage: isLastOwnUserMessage, onRetry: onRetry, isStreamingAny: pairedAssistantStreaming, allMessages: $messages)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 50) // Height of the bottom overlay
            }
        }
    }
}