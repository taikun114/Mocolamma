import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContainerHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 600
}

extension EnvironmentValues {
    var containerHeight: CGFloat {
        get { self[ContainerHeightKey.self] }
        set { self[ContainerHeightKey.self] = newValue }
    }
}

struct ChatMessagesView: View {
    @Environment(CommandExecutor.self) var executor
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    let isUsingSafeAreaBar: Bool
    var bottomInset: CGFloat = 0
    
    // 空の状態の表示をカスタマイズするための引数を追加
    let emptyStateTitle: LocalizedStringKey
    let emptyStateDescription: LocalizedStringKey
    let emptyStateImage: String
    
    private var reduceMotionEnabled: Bool {
#if !os(macOS)
        return UIAccessibility.isReduceMotionEnabled
#elseif os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#else
        return false
#endif
    }
    
    private var supportsEffects: Bool {
#if os(macOS) || os(iOS)
        if #available(iOS 26, macOS 26, *) { return true }
#endif
        return false
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ChatMessagesScrollView(
                    messages: $messages,
                    onRetry: onRetry,
                    isOverallStreaming: $isOverallStreaming,
                    isModelSelected: isModelSelected,
                    supportsEffects: supportsEffects,
                    reduceMotionEnabled: reduceMotionEnabled,
                    isUsingSafeAreaBar: isUsingSafeAreaBar,
                    bottomInset: bottomInset
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
                    ImagePreviewOverlay(image: image, onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            executor.previewImage = nil
                        }
                    }, bottomInset: bottomInset)
                    .zIndex(100)
                }
            }
            .contentShape(Rectangle())
#if !os(macOS)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
#endif
            .environment(\.containerHeight, geometry.size.height)
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
    var bottomInset: CGFloat = 0
    
    @State private var isNearBottom: Bool = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // LazyVStackからVStackに変更してレイアウトの安定性を確保
                // LazyVStackでは急激なスクロールや表示エリア変更時にCPU使用率が100%に張り付いて無限にフリーズしてしまう問題が発生するため
                VStack(alignment: .leading, spacing: 10) {
                    let lastAssistantId = messages.last(where: { $0.role == "assistant" })?.id
                    let lastUserId = messages.last(where: { $0.role == "user" })?.id
                    
                    ForEach(messages) { message in
                        MessageViewWrapper(
                            message: message,
                            isLastAssistantMessage: message.id == lastAssistantId,
                            isLastOwnUserMessage: message.id == lastUserId,
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
                
                if bottomInset > 0 {
                    Spacer(minLength: bottomInset)
                }
                
                Spacer().id("bottom-spacer")
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .modifier(SoftEdgeIfAvailable(enabled: supportsEffects))
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let contentHeight = geometry.contentSize.height
                let visibleHeight = geometry.containerSize.height
                let scrollOffset = geometry.contentOffset.y
                
                // iOSでのバウンスやセーフエリアを考慮した計算
                let maxOffset = max(0, contentHeight - visibleHeight)
                let distanceFromBottom = maxOffset - scrollOffset
                
                // 200px以内なら「底に近い」と判定（安定性と手動操作のバランスを考慮）
                return distanceFromBottom < 200 || scrollOffset > maxOffset - 5
            } action: { _, newValue in
                isNearBottom = newValue
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { oldHeight, newHeight in
                // ユーザーが底付近にいる場合のみ、コンテンツが伸びたらスクロール追従
                if isNearBottom && newHeight > oldHeight {
                    scrollBottom(proxy: proxy)
                }
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if newCount > oldCount {
                    // 新しいメッセージが追加されたときは、現在の位置に関わらず底に移動（UX上の期待値）
                    scrollBottom(proxy: proxy)
                }
            }
            // 最後のメッセージの内容（ストリーミング）が開始・終了した際
            .onChange(of: isOverallStreaming) { _, _ in
                // ユーザーが底付近にいる場合のみ、完了時などのレイアウト変更に追従
                if isNearBottom {
                    scrollBottom(proxy: proxy)
                }
            }
        }
    }
    
    private func scrollBottom(proxy: ScrollViewProxy) {
        Task {
            // 1回目のスクロール：即応性を重視
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            withAnimation(reduceMotionEnabled ? .none : .default) {
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
            
            // 2回目のスクロール：レイアウトが完全に落ち着いた後の微調整用
            // 50ms〜100ms程度待つことで、複雑なレイアウト変更（ボタンの出現など）後の位置を確定させる
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            withAnimation(reduceMotionEnabled ? .none : .default) {
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
        }
    }
}

struct MessageViewWrapper: View {
    let message: ChatMessage
    let isLastAssistantMessage: Bool
    let isLastOwnUserMessage: Bool
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    
    var body: some View {
        MessageView(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isLastOwnUserMessage: isLastOwnUserMessage,
            onRetry: onRetry,
            isStreamingAny: $isOverallStreaming,
            isModelSelected: isModelSelected
        )
    }
}
