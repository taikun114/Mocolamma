import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ChatMessagesView: View {
    @Environment(CommandExecutor.self) var executor
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    let isUsingSafeAreaBar: Bool
    
    // 空の状態の表示をカスタマイズするための引数を追加
    let emptyStateTitle: LocalizedStringKey
    let emptyStateDescription: LocalizedStringKey
    let emptyStateImage: String
    
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
        ZStack {
            ChatMessagesScrollView(
                messages: $messages,
                onRetry: onRetry,
                isOverallStreaming: $isOverallStreaming,
                isModelSelected: isModelSelected,
                supportsEffects: supportsEffects,
                reduceMotionEnabled: reduceMotionEnabled,
                isUsingSafeAreaBar: isUsingSafeAreaBar
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if messages.isEmpty {
                ContentUnavailableView {
                    Label(emptyStateTitle, systemImage: emptyStateImage)
                } description: {
                    Text(emptyStateDescription)
                }
            }
            
            // 拡大表示オーバーレイ
            if let image = executor.previewImage {
                ImagePreviewOverlay(image: image) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        executor.previewImage = nil
                    }
                }
                .zIndex(100)
            }
        }
        .onDrop(of: [.fileURL, .image], delegate: AreaImageDropDelegate(items: .constant([]), isDraggingOver: .constant(false), executor: executor))
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
                // LazyVStackからVStackに変更してレイアウトの安定性を確保
                VStack(alignment: .leading, spacing: 10) {
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
                if newCount > oldCount {
                    // 新しいメッセージが追加されたときのみスクロール
                    scrollBottom(proxy: proxy)
                }
            }
            // 最後のメッセージの内容（ストリーミング）が更新された時も追従したい場合
            .onChange(of: isOverallStreaming) { _, newValue in
                if newValue {
                    scrollBottom(proxy: proxy)
                }
            }
        }
    }
    
    private func scrollBottom(proxy: ScrollViewProxy) {
        Task {
            // レイアウト確定を待つための最小限の遅延
            try? await Task.sleep(nanoseconds: 50_000_000) 
            withAnimation(reduceMotionEnabled ? .none : .default) {
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
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
