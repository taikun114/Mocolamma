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
    @Environment(ChatSettings.self) var chatSettings
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    @Binding var isNearBottom: Bool
    @Binding var scrollToBottomTrigger: Int
    let isModelSelected: Bool
    var bottomInset: CGFloat = 0
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
                    isNearBottom: $isNearBottom,
                    scrollToBottomTrigger: $scrollToBottomTrigger,
                    isModelSelected: isModelSelected,
                    supportsEffects: supportsEffects,
                    reduceMotionEnabled: reduceMotionEnabled,
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

struct ScrollState: Hashable, Equatable {
    let nearBottom: Bool
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let contentOffset: CGPoint
}

struct ChatMessagesScrollView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ChatSettings.self) var chatSettings
    @Binding var messages: [ChatMessage]
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isOverallStreaming: Bool
    @Binding var isNearBottom: Bool
    @Binding var scrollToBottomTrigger: Int
    let isModelSelected: Bool
    let supportsEffects: Bool
    let reduceMotionEnabled: Bool
    var bottomInset: CGFloat = 0
    
    @State private var lastScrollTime: Date = .distantPast
    @State private var lastStateUpdateTime: Date = .distantPast
    @State private var isUserInteracting: Bool = false
    @GestureState private var isTouching: Bool = false
    @State private var latestScrollState: ScrollState? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // メッセージリストとその高さ監視ロジックをSubviewに切り出し、
                // 頻繁な高さ変更（1トークンごと）がScrollView全体や親ビューの再描画を
                // 引き起こさないように局所化（Fundamental Fix）
                MessagesList(
                    messages: $messages,
                    isOverallStreaming: $isOverallStreaming,
                    isModelSelected: isModelSelected,
                    onRetry: onRetry
                )
                
                Spacer().frame(height: 1).id("bottom-spacer")
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .modifier(SoftEdgeIfAvailable(enabled: supportsEffects))
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting || newPhase == .decelerating {
                    isUserInteracting = true
                } else if newPhase == .idle {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isUserInteracting = false
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouching) { _, state, _ in
                        state = true
                    }
            )
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                let contentHeight = geometry.contentSize.height
                let visibleHeight = geometry.containerSize.height
                let scrollOffset = geometry.contentOffset.y
                let maxOffset = max(0, contentHeight - visibleHeight)
                let distanceFromBottom = maxOffset - scrollOffset
                
                let threshold: CGFloat = 300 + bottomInset
                let nearBottom = distanceFromBottom < threshold || scrollOffset > maxOffset - 10
                
                return ScrollState(
                    nearBottom: nearBottom,
                    contentHeight: contentHeight,
                    containerHeight: visibleHeight,
                    contentOffset: geometry.contentOffset
                )
            } action: { _, newValue in
                // ストリーミング中は最新のスクロール状態の更新をスロットリング（10Hz）し、
                // RTIInputSystemClient（テキスト入力管理）への負荷を軽減する
                let now = Date()
                if !isOverallStreaming || now.timeIntervalSince(lastStateUpdateTime) >= 0.1 {
                    latestScrollState = newValue
                    lastStateUpdateTime = now
                    isNearBottom = newValue.nearBottom
                }
            }
            .task(id: isOverallStreaming) {
                if isOverallStreaming {
                    while !Task.isCancelled {
                        do {
                            // 15fps程度（約0.06s間隔）でチェックを行い、必要ならスクロール
                            // 高頻度なスクロール命令によるオーバーヘッドを抑制
                            try await Task.sleep(nanoseconds: 66_666_666)
                            
                            if let state = latestScrollState {
                                let isUserSent = messages.last?.role == "user"
                                let now = Date()
                                let shouldScroll = isUserSent || state.nearBottom
                                
                                if shouldScroll && !isTouching && !isUserInteracting && state.contentHeight > 0 && now.timeIntervalSince(lastScrollTime) >= 0.05 {
                                    lastScrollTime = now
                                    // [CRITICAL] ストリーミング中はアニメーションなしでスクロール
                                    // 30Hz近くでアニメーションを開始し続けると、visionOSのレイアウトエンジンが飽和し、
                                    // 1メッセージだけでも100%負荷になります。
                                    scrollBottom(proxy: proxy, force: isUserSent, animated: false)
                                }
                            }
                        } catch {
                            break
                        }
                    }
                } else {
                    let isUserSent = messages.last?.role == "user"
                    if latestScrollState?.nearBottom ?? false || isUserSent {
                        scrollBottom(proxy: proxy, force: isUserSent, animated: true)
                    }
                }
            }
            .onChange(of: isOverallStreaming) { _, newValue in
                if newValue {
                    scrollBottom(proxy: proxy, force: true, animated: true)
                }
            }
            .onChange(of: scrollToBottomTrigger) { _, _ in
                scrollBottom(proxy: proxy, force: true, animated: true)
            }
        }
    }
    
    private func scrollBottom(proxy: ScrollViewProxy, force: Bool = false, animated: Bool = true) {
        if force || (latestScrollState?.nearBottom ?? false) {
            if animated && !reduceMotionEnabled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("bottom-spacer", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
        }
    }
}

// MARK: - Subviews

/// メッセージのリスト表示と高さ監視をカプセル化するビュー
/// このビュー内での高さ変更による再描画を親（ScrollView）に波及させない
struct MessagesList: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ChatSettings.self) var chatSettings
    @Binding var messages: [ChatMessage]
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    let onRetry: ((UUID, ChatMessage) -> Void)?
    
    @State private var maxMessagesHeight: CGFloat = 0
    @State private var currentMessagesHeight: CGFloat = 0
    @State private var lastGeometryUpdateTime: Date = .distantPast
    
    // パフォーマンス最適化のためのメモ化された状態
    @State private var lastAssistantId: UUID? = nil
    @State private var lastUserId: UUID? = nil
    @State private var memoizedModelName: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                MessageViewWrapper(
                    message: message,
                    isLastAssistantMessage: message.id == lastAssistantId,
                    isLastOwnUserMessage: message.id == lastUserId,
                    selectedModelName: memoizedModelName,
                    onRetry: onRetry,
                    onPreviewImage: { image in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            executor.previewImage = image
                        }
                    },
                    isOverallStreaming: $isOverallStreaming,
                    isModelSelected: isModelSelected
                )
                .id(message.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            // ストリーミング中はレイアウト計算の連鎖を防ぐため、高階層のState更新をスロットリング（5Hz）
            let now = Date()
            if !isOverallStreaming || now.timeIntervalSince(lastGeometryUpdateTime) >= 0.2 {
                currentMessagesHeight = newValue
                if newValue > maxMessagesHeight {
                    maxMessagesHeight = newValue
                }
                lastGeometryUpdateTime = now
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat messages")
        .padding()
        .onChange(of: isOverallStreaming, initial: true) { _, newValue in
            if newValue {
                maxMessagesHeight = 0
            }
            updateMemoizedState()
        }
        .onChange(of: messages.count, initial: true) { _, _ in
            maxMessagesHeight = 0
            updateMemoizedState()
        }
        .onChange(of: chatSettings.selectedModelID) { _, _ in
            updateMemoizedState()
        }
        
        if maxMessagesHeight > currentMessagesHeight {
            Spacer(minLength: maxMessagesHeight - currentMessagesHeight)
        }
    }
    
    private func updateMemoizedState() {
        lastAssistantId = messages.last(where: { $0.role == "assistant" })?.id
        lastUserId = messages.last(where: { $0.role == "user" })?.id
        memoizedModelName = chatSettings.selectedModelID.flatMap { executor.modelsByID[$0]?.name }
    }
}

struct MessageViewWrapper: View, Equatable {
    let message: ChatMessage
    let isLastAssistantMessage: Bool
    let isLastOwnUserMessage: Bool
    let selectedModelName: String?
    let onRetry: ((UUID, ChatMessage) -> Void)?
    let onPreviewImage: ((PlatformImage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    
    static func == (lhs: MessageViewWrapper, rhs: MessageViewWrapper) -> Bool {
        // オブジェクトの同一性をチェック（基本同じインスタンスであることを前提）
        guard lhs.message === rhs.message else { return false }
        
        // 基本属性の変更をチェック
        if lhs.isLastAssistantMessage != rhs.isLastAssistantMessage ||
           lhs.isLastOwnUserMessage != rhs.isLastOwnUserMessage ||
           lhs.isModelSelected != rhs.isModelSelected ||
           lhs.selectedModelName != rhs.selectedModelName ||
           lhs.isOverallStreaming != rhs.isOverallStreaming {
            return false
        }
        
        // [CRITICAL] ストリーミング中または画像処理中の場合のみ、重い文字列比較を行う。
        // これにより、膨大な過去メッセージ（数千〜数万文字）に対する毎フレームの文字列比較を回避し、CPU負荷を劇的に低減する。
        if lhs.message.isStreaming || lhs.message.isProcessingImages || rhs.message.isStreaming {
            return lhs.message.content == rhs.message.content &&
                   lhs.message.thinking == rhs.message.thinking &&
                   lhs.message.isThinkingCompleted == rhs.message.isThinkingCompleted
        }
        
        // 完了済みメッセージについては、メタデータのみ比較
        return lhs.message.isStopped == rhs.message.isStopped &&
               lhs.message.isCopied == rhs.message.isCopied &&
               lhs.message.currentRevisionIndex == rhs.message.currentRevisionIndex &&
               lhs.message.revisions.count == rhs.message.revisions.count &&
               lhs.message.isDownloadSuccessful == rhs.message.isDownloadSuccessful
    }
    
    var body: some View {
        MessageView(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isLastOwnUserMessage: isLastOwnUserMessage,
            selectedModelName: selectedModelName,
            onRetry: onRetry,
            onPreviewImage: onPreviewImage,
            isStreamingAny: $isOverallStreaming,
            isModelSelected: isModelSelected
        )
    }
}
