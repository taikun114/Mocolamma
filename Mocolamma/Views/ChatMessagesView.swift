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

struct ScrollState: Equatable {
    let nearBottom: Bool
    let contentHeight: CGFloat
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
    @State private var lastScrollTime: Date = .distantPast
    @State private var isUserInteracting: Bool = false
    @GestureState private var isTouching: Bool = false
    @State private var latestScrollState: ScrollState? = nil
    
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
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Chat messages")
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
                
                let threshold: CGFloat = 800 // より広めに設定
                let nearBottom = distanceFromBottom < threshold || scrollOffset > maxOffset - 10
                
                return ScrollState(nearBottom: nearBottom, contentHeight: contentHeight)
            } action: { _, newValue in
                // 変更があった時のみシグナルを送る
                if latestScrollState != newValue {
                    latestScrollState = newValue
                }
            }
            .task(id: latestScrollState) {
                guard let state = latestScrollState else { return }
                do {
                    // ループを止める最小限のディレイ。1.5フレーム分（約25ms）程度待つことで
                    // OS側のジオメトリ計算が完全に落ち着くのを待ちます。
                    try await Task.sleep(nanoseconds: 25_000_000)
                    
                    await MainActor.run {
                        // 状態の不一致がある場合のみ更新
                        if isNearBottom != state.nearBottom {
                            isNearBottom = state.nearBottom
                        }
                        
                        let now = Date()
                        // 追従頻度をさらに最適化（0.15秒）
                        if state.nearBottom && !isTouching && !isUserInteracting && state.contentHeight > 0 && now.timeIntervalSince(lastScrollTime) >= 0.15 {
                            lastScrollTime = now
                            scrollBottom(proxy: proxy)
                        }
                    }
                } catch {}
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if newCount > oldCount {
                    DispatchQueue.main.async {
                        scrollBottom(proxy: proxy)
                    }
                }
            }
            .onChange(of: isOverallStreaming) { _, _ in
                if isNearBottom {
                    DispatchQueue.main.async {
                        scrollBottom(proxy: proxy)
                    }
                }
            }
        }
    }
    
    private func scrollBottom(proxy: ScrollViewProxy) {
        // すでに実行中のスクロールタスクがある場合は無視されるように設計
        // レイアウト変更（選択ボタン出現など）が完全に完了するまで少し待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
