import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ChatMessagesView: View {
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    let isUsingSafeAreaBar: Bool
    
    private var reduceMotionEnabled: Bool {
#if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
#elseif os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#else
        return false
#endif
    }
    
    private var supportsEffects: Bool {
#if os(iOS)
        if #available(iOS 26, *) { return true } else { return false }
#else
        if #available(macOS 26, *) { return true } else { return false }
#endif
    }
    
    var body: some View {
        ChatMessagesScrollView(
            messages: $messages,
            onRetry: onRetry,
            isOverallStreaming: $isOverallStreaming,
            isModelSelected: isModelSelected,
            supportsEffects: supportsEffects,
            reduceMotionEnabled: reduceMotionEnabled,
            isUsingSafeAreaBar: isUsingSafeAreaBar
        )
    }
}

struct ChatMessagesScrollView: View {
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    let supportsEffects: Bool
    let reduceMotionEnabled: Bool
    let isUsingSafeAreaBar: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageViewWrapper(
                            message: message,
                            messages: $messages,
                            onRetry: onRetry,
                            isOverallStreaming: $isOverallStreaming,
                            isModelSelected: isModelSelected
                        )
                        .id(message.id)
                    }
                }
                .padding()
                .if(!isUsingSafeAreaBar) { view in
                    view.padding(.bottom, 50)
                }
                Spacer().id("bottom-spacer")
            }
            .modifier(SoftEdgeIfAvailable(enabled: supportsEffects))
            .onChange(of: messages.count) { oldCount, newCount in
                if newCount > oldCount, let lastMessage = messages.last, lastMessage.role == "assistant" {
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待機
                        withAnimation(reduceMotionEnabled ? .none : .default) {
                            proxy.scrollTo("bottom-spacer", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct MessageViewWrapper: View {
    let message: ChatMessage
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    
    private var isLastAssistantMessage: Bool {
        message.role == "assistant" && messages.last?.id == message.id
    }
    
    private var isLastOwnUserMessage: Bool {
        message.role == "user" && messages.last(where: { $0.role == "user" })?.id == message.id
    }
    
    var body: some View {
        MessageView(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isLastOwnUserMessage: isLastOwnUserMessage,
            onRetry: onRetry,
            isStreamingAny: $isOverallStreaming,
            allMessages: $messages,
            isModelSelected: isModelSelected
        )
    }
}
