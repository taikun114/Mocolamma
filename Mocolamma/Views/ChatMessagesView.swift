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

struct ScrollState: Hashable, Equatable {
    let nearBottom: Bool
    let contentHeight: CGFloat
}

struct ChatMessagesScrollView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ChatSettings.self) var chatSettings
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
                        let modelName = chatSettings.selectedModelID.flatMap { executor.modelsByID[$0]?.name }
                        MessageViewWrapper(
                            message: message,
                            isLastAssistantMessage: message.id == lastAssistantId,
                            isLastOwnUserMessage: message.id == lastUserId,
                            selectedModelName: modelName,
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
                // コンテンツの高さの変化が微細な場合は無視して負荷を下げる
                let heightChanged = abs((latestScrollState?.contentHeight ?? 0) - newValue.contentHeight) > 2.0
                let nearBottomChanged = (latestScrollState?.nearBottom ?? false) != newValue.nearBottom
                
                if heightChanged || nearBottomChanged {
                    latestScrollState = newValue
                }
            }
            .task(id: latestScrollState) {
                guard let state = latestScrollState else { return }
                do {
                    // ループを止める最小限のディレイ
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
            .task(id: messages.count) {
                do {
                    // メッセージの増加を検知した際の防振
                    try await Task.sleep(nanoseconds: 50_000_000)
                    
                    await MainActor.run {
                        scrollBottom(proxy: proxy)
                    }
                } catch {}
            }
            .task(id: isOverallStreaming) {
                if !isOverallStreaming {
                    // ストリーミング完了時は、レイアウト（選択ボタンの出現など）の確定を待つために少し待機
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    await MainActor.run {
                        if isNearBottom {
                            scrollBottom(proxy: proxy)
                        }
                    }
                } else if isNearBottom {
                    await MainActor.run {
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

struct MessageViewWrapper: View, Equatable {
    let message: ChatMessage
    let isLastAssistantMessage: Bool
    let isLastOwnUserMessage: Bool
    let selectedModelName: String?
    let onRetry: ((UUID, ChatMessage) -> Void)?
    let onPreviewImage: ((PlatformImage) -> Void)?
    @Binding var isOverallStreaming: Bool
    let isModelSelected: Bool
    
    // Equatableの実装
    static func == (lhs: MessageViewWrapper, rhs: MessageViewWrapper) -> Bool {
        // メッセージオブジェクト自体が異なる場合は再描画
        guard lhs.message === rhs.message else { return false }
        
        // メッセージの内容や状態が変更されている場合は再描画が必要。
        // ※ Observableクラスのプロパティ変更はSwiftUIが個別に検知しますが、
        //   View全体の再評価を抑えるためにEquatableで明示的にチェックします。
        return lhs.message.content == rhs.message.content &&
               lhs.message.thinking == rhs.message.thinking &&
               lhs.message.isStreaming == rhs.message.isStreaming &&
               lhs.message.isStopped == rhs.message.isStopped &&
               lhs.message.isCopied == rhs.message.isCopied &&
               lhs.message.isDownloadSuccessful == rhs.message.isDownloadSuccessful &&
               lhs.message.currentRevisionIndex == rhs.message.currentRevisionIndex &&
               lhs.message.revisions.count == rhs.message.revisions.count &&
               lhs.isLastAssistantMessage == rhs.isLastAssistantMessage &&
               lhs.isLastOwnUserMessage == rhs.isLastOwnUserMessage &&
               lhs.isModelSelected == rhs.isModelSelected &&
               lhs.selectedModelName == rhs.selectedModelName &&
               lhs.isOverallStreaming == rhs.isOverallStreaming
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
