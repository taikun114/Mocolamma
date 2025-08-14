import SwiftUI

struct ChatMessagesView: View {
    @Binding var messages: [ChatMessage]
     let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool // New binding
    let isModelSelected: Bool

    var body: some View {        let supportsEffects: Bool = {
        #if os(iOS)
            if #available(iOS 26, *) { return true } else { return false }
        #else
            if #available(macOS 26, *) { return true } else { return false }
        #endif
        }()
         ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        let isLastAssistantMessage = message.role == "assistant" && messages.last?.id == message.id
                        let isLastOwnUserMessage = message.role == "user" && messages.last(where: { $0.role == "user" })?.id == message.id
                        MessageView(message: message, isLastAssistantMessage: isLastAssistantMessage, isLastOwnUserMessage: isLastOwnUserMessage, onRetry: onRetry, isStreamingAny: $isOverallStreaming, allMessages: $messages, isModelSelected: isModelSelected) // Pass $isOverallStreaming
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 50)
            }
            .modifier(SoftEdgeIfAvailable(enabled: supportsEffects))
    }
}