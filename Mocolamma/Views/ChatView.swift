import SwiftUI
import StoreKit
import Textual
import ImageIO
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ServerManager.self) var serverManager
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    @Environment(ChatSettings.self) var chatSettings
    @Environment(\.requestReview) var requestReview
    
    @State private var errorMessage: String?
    @State private var showUnsupportedModelAlert: Bool = false
    @State private var showingVisionWarningAlert: Bool = false
    @State private var generalErrorMessage: String? = nil
    @State private var showingNewChatConfirm: Bool = false
    @State private var inputAreaHeight: CGFloat = 0
    @State private var isNearBottom: Bool = true
    @State private var scrollToBottomTrigger: Int = 0
    @State private var scrollToMessageIDTrigger: UUID? = nil
    private var modelSettings = ModelSettingsManager.shared
    @State private var selectionCoordinator = TextSelectionCoordinator()

    
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
    
    init(showingInspector: Binding<Bool>, onToggleInspector: @escaping () -> Void) {
        self._showingInspector = showingInspector
        self.onToggleInspector = onToggleInspector
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var currentSelectedModel: OllamaModel? {
        if let id = chatSettings.selectedModelID {
            return executor.models.first(where: { $0.id == id })
        }
        return nil
    }
    
    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }
    
    @ViewBuilder
    private var chatContent: some View {
        @Bindable var executor = executor
        ZStack {
            if serverManager.selectedServer == nil {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "server.rack",
                    description: Text("Please select a server in the Server tab.")
                )
            } else if executor.apiConnectionError {
                ContentUnavailableView(
                    "Connection Failed",
                    systemImage: "network.slash",
                    description: Text(LocalizedStringKey(executor.specificConnectionErrorMessage ?? "Failed to connect to the Ollama API. Please check your network connection or server settings."))
                )
            } else {
                ChatMessagesView(
                    messages: $executor.chatMessages,
                    onRetry: retryMessage,
                    isOverallStreaming: $executor.isChatStreaming,
                    isNearBottom: $isNearBottom,
                    scrollToBottomTrigger: $scrollToBottomTrigger,
                    scrollToMessageIDTrigger: $scrollToMessageIDTrigger,
                    isModelSelected: chatSettings.selectedModelID != nil,
                    bottomInset: inputAreaHeight,
                    emptyStateTitle: "Chat",
                    emptyStateDescription: "Here you can perform a simple chat to check the model.",
                    emptyStateImage: "message.fill"
                )
            }
        }
        .frame(maxHeight: .infinity) // Make sure it fills the available height
    }
    
    @ViewBuilder
    private func makeSafeAreaBarContent() -> some View {
        @Bindable var executor = executor
        VStack(spacing: 0) {
#if !os(visionOS)
            ScrollToBottomButton(isNearBottom: isNearBottom, messagesEmpty: executor.chatMessages.isEmpty, scrollToBottomTrigger: $scrollToBottomTrigger)
#endif
            
            ChatInputView(inputText: $executor.chatInputText, selectedImages: $executor.chatInputImages, isStreaming: $executor.isChatStreaming, showingInspector: $showingInspector, placeholder: "Type your message...", selectedModel: currentSelectedModel) {
                sendMessage()
            } stopMessage: {
                if let lastAssistantMessageIndex = executor.chatMessages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    executor.chatMessages[lastAssistantMessageIndex].isStreaming = false
                    executor.chatMessages[lastAssistantMessageIndex].isStopped = true
                    executor.updateIsChatStreaming()
                }
                executor.isChatStreaming = false
                executor.cancelChatStreaming()
            }
        }
        .animation(.spring(duration: 0.3), value: executor.chatMessages.isEmpty)
#if !os(visionOS)
        .padding()
#endif
#if os(visionOS)
        .onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.height + 32) / 2
        } action: { newValue in
            inputAreaHeight = newValue
        }
#endif
    }
    
    var body: some View {
        @Bindable var executor = executor
        Group {
#if os(visionOS)
            ZStack(alignment: .bottom) {
                if #available(visionOS 26.0, *) {
                    chatContent
                        .safeAreaBar(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                } else {
                    chatContent
                        .safeAreaInset(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                }

                ZStack(alignment: .bottom) {
                    ScrollToBottomButton(isNearBottom: isNearBottom, messagesEmpty: executor.chatMessages.isEmpty, scrollToBottomTrigger: $scrollToBottomTrigger)
                        .padding(.bottom, inputAreaHeight + 8)
                }
                .animation(.spring(duration: 0.3), value: isNearBottom)
                .animation(.spring(duration: 0.3), value: executor.chatMessages.isEmpty)
            }
            .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
                makeSafeAreaBarContent()
                    .frame(width: 600)
                    .padding(16)
                    .glassBackgroundEffect()
            }
#elseif os(iOS)
            if #available(iOS 26.0, *) {
                chatContent
                    .safeAreaBar(edge: .bottom) {
                        makeSafeAreaBarContent()
                    }
            } else {
                chatContent
                    .safeAreaInset(edge: .bottom) {
                        makeSafeAreaBarContent()
                            .if(horizontalSizeClass != .compact) { view in
                                view.ignoresSafeArea(.container, edges: [.bottom])
                            }
                    }
            }
#else
            if #available(macOS 26.0, *) {
                chatContent
                    .safeAreaBar(edge: .bottom) {
                        makeSafeAreaBarContent()
                    }
            } else {
                chatContent
                    .safeAreaInset(edge: .bottom) {
                        makeSafeAreaBarContent()
                    }
            }
#endif
        }
#if !os(macOS)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            selectionCoordinator.deselectAll()
        }
#endif
        .environment(selectionCoordinator)
        .modifier(TextSelectionCoordination())
        .navigationTitle("Chat")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear {
            if let current = chatSettings.selectedModelID, !executor.models.contains(where: { $0.id == current }) {
                chatSettings.selectedModelID = nil
            }
        }
        .onDrop(of: [.fileURL, .image], delegate: AreaImageDropDelegate(items: .constant([]), isDraggingOver: .constant(false), executor: executor, isEnabled: currentSelectedModel?.supportsVision ?? false))
        .task {
            // サーバーが選択されており、かつ初期フェッチが未完了の場合のみ自動リフレッシュを実行
            if serverManager.selectedServer != nil && !executor.initialFetchCompleted && !executor.isRunning && !executor.isPulling {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    appRefreshTrigger.send()
                }
            }
        }
        .onChange(of: executor.models) { _, newModels in
            // モデルリストが更新された際、選択中のモデルが新しいリストに存在するか確認
            if let currentSelectedModelID = chatSettings.selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
                // 存在しない場合は選択を解除
                chatSettings.selectedModelID = nil
            }
        }
        .onChange(of: chatSettings.selectedModelID) { _, _ in
            handleModelSelectionChange()
        }
        .alert("This model cannot be used", isPresented: $showUnsupportedModelAlert) {
            unsupportedModelAlertContent
        } message: {
            Text(String(localized: "This model does not support chat.", comment: "ユーザがチャットに埋め込み専用モデルを使用しようとしたときのエラーメッセージ。"))
        }
        .alert("This model does not support images", isPresented: $showingVisionWarningAlert) {
            Button("Send") {
                if let model = currentSelectedModel {
                    performSendMessage(model: model, skipImages: true)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if let modelName = currentSelectedModel?.name {
                Text("The selected model \"\(modelName)\" does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            } else {
                Text("The selected model does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            }
        }
        .alert(Text("Error Occurred"), isPresented: Binding<Bool>(
            get: { generalErrorMessage != nil },
            set: { if !$0 { generalErrorMessage = nil } }
        )) {
            errorAlertContent
        } message: {
            Text(generalErrorMessage ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private var unsupportedModelAlertContent: some View {
        Button("OK") { showUnsupportedModelAlert = false }
            .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private var errorAlertContent: some View {
        Button("OK") { generalErrorMessage = nil }
            .keyboardShortcut(.defaultAction)
    }

    private func handleModelSelectionChange() {
        chatSettings.contextWindowValue = 2048.0
        guard let model = currentSelectedModel else {
            chatSettings.selectedModelContextLength = nil
            chatSettings.selectedModelCapabilities = nil
            return
        }
        Task {
            if let response = await executor.fetchModelInfo(modelName: model.name) {
                let contextLength: Int?
                if let modelInfo = response.model_info,
                   let contextLengthValue = modelInfo.first(where: { $0.key.hasSuffix(".context_length") })?.value,
                   case .int(let length) = contextLengthValue {
                    contextLength = length
                } else {
                    contextLength = nil
                }
                let isUnsupportedModel = {
                    let caps = response.capabilities ?? []
                    let detFamilies = response.details?.families ?? []
                    
                    // 埋め込みモデルの判定
                    let isEmbedding = !caps.isEmpty && caps.allSatisfy { $0.lowercased() == "embedding" || $0.lowercased() == "embeddings" }
                    let isEmbeddingFamily = !detFamilies.isEmpty && detFamilies.count == 1 && detFamilies.first?.lowercased() == "embedding"
                    
                    // 画像生成モデルの判定（イメージのみの場合）
                    let isImage = !caps.isEmpty && caps.allSatisfy { $0.lowercased() == "image" }
                    
                    return isEmbedding || isEmbeddingFamily || isImage
                }()
                
                if isUnsupportedModel {
                    chatSettings.selectedModelID = nil
                    showUnsupportedModelAlert = true
                    return
                }
                chatSettings.selectedModelContextLength = contextLength
                chatSettings.selectedModelCapabilities = response.capabilities
            } else {
                chatSettings.selectedModelContextLength = nil
                chatSettings.selectedModelCapabilities = nil
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var chatSettings = chatSettings
        @Bindable var executor = executor
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling)
        }
        
        ToolbarItem(placement: .primaryAction) {
            Picker("Select Model", selection: $chatSettings.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                let sortedModels = executor.models.filter { $0.supportsCompletion }.sorted(using: modelSettings.sortOrder(forChat: true))
                ForEach(sortedModels) { model in
                    let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                    HStack {
                        Text(model.name)
                        if isRunning { Image(systemName: "tray.and.arrow.down") }
                    }
                    .tag(model.id as OllamaModel.ID?)
                }
                if executor.models.filter({ $0.supportsCompletion }).isEmpty {
                    Divider()
                    if executor.isRunning {
                        Text("Loading models...")
                            .tag("loading-models-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    } else {
                        Text("No models available")
                            .tag("no-models-available-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !executor.chatMessages.isEmpty { showingNewChatConfirm = true }
            }) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .disabled(executor.chatMessages.isEmpty)
            .confirmationDialog(String(localized: "Are you sure you want to clear the chat history?"), isPresented: $showingNewChatConfirm, titleVisibility: .visible) {
                Button(String(localized: "Clear Chat History"), role: .destructive) {
                    executor.clearChat()
                    executor.isChatStreaming = false
                    errorMessage = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }
#else
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling)
            
            Menu {
                Section {
                    Picker("Select Model", selection: $chatSettings.selectedModelID) {
                        Text("Select Model").tag(nil as OllamaModel.ID?)
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Picker("Models", selection: $chatSettings.selectedModelID) {
                        let sortedModels = executor.models.filter { $0.supportsCompletion }.sorted(using: modelSettings.sortOrder(forChat: true))
                        ForEach(sortedModels) { model in
                            let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                            HStack {
                                Text(model.name)
                                if isRunning { Image(systemName: "tray.and.arrow.down") }
                            }
                            .tag(model.id as OllamaModel.ID?)
                        }
                    }
                    .pickerStyle(.inline)
                }
                if executor.models.filter({ $0.supportsCompletion }).isEmpty {
                    Section {
                        if executor.isRunning {
                            Button(action: {}) { Text("Loading models...") }.disabled(true)
                        } else {
                            Button(action: {}) { Text("No models available") }.disabled(true)
                        }
                    }
                }
            } label: {
                let selectedModelName = executor.models.first(where: { $0.id == chatSettings.selectedModelID })?.name
                Label(selectedModelName ?? String(localized: "Select Model"), systemImage: chatSettings.selectedModelID != nil ? "tray.full.fill" : "tray.full")
#if os(visionOS)
                    .labelStyle(.titleAndIcon)
#endif
            }
            .help({
                if let selectedModelName = executor.models.first(where: { $0.id == chatSettings.selectedModelID })?.name {
                    return String(format: NSLocalizedString("Select Model (%@ Selected)", comment: "モデルが選択されている時のツールチップ。"), selectedModelName)
                }
                return String(localized: "Select Model")
            }())
        }
        
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !executor.chatMessages.isEmpty { showingNewChatConfirm = true }
            }) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .disabled(executor.chatMessages.isEmpty)
            .confirmationDialog(String(localized: "Are you sure you want to clear the chat history?"), isPresented: $showingNewChatConfirm, titleVisibility: .visible) {
                Button(String(localized: "Clear Chat History"), role: .destructive) {
                    executor.clearChat()
                    executor.isChatStreaming = false
                    errorMessage = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }
        
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif

        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: (isNativeVisionOS || isiOSAppOnVision) ? "info.circle" : (horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing"))
            }
        }
#endif
    }
    
    private func sendMessage() {
        ReviewManager.shared.requestReviewIfAppropriate(requestReviewAction: requestReview)
        
        generalErrorMessage = nil
        guard let model = currentSelectedModel else {
            generalErrorMessage = "Please select a model first."
            return
        }
        guard !executor.chatInputText.isEmpty || !executor.chatInputImages.isEmpty else { return }
        
        // ビジョン非対応モデルで画像がある場合の警告チェック
        if !executor.chatInputImages.isEmpty && !model.supportsVision {
            showingVisionWarningAlert = true
            return
        }
        
        performSendMessage(model: model)
    }
    
    private func performSendMessage(model: OllamaModel, skipImages: Bool = false) {
        let text = executor.chatInputText
        let imagesData = skipImages ? [] : executor.chatInputImages.map { $0.data }
        
        executor.chatInputText = ""
        if !skipImages {
            executor.chatInputImages = []
        }
        executor.isChatStreaming = true
        
        let userMessage = ChatMessage(role: "user", content: text, images: nil, createdAt: MessageView.iso8601Formatter.string(from: Date()))
        userMessage.isProcessingImages = !imagesData.isEmpty
        executor.chatMessages.append(userMessage)
        
        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        placeholderMessage.revisions = []
        placeholderMessage.currentRevisionIndex = 0
        placeholderMessage.originalContent = ""
        placeholderMessage.latestContent = ""
        executor.chatMessages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id
        
        Task {
            // 画像がある場合はバックグラウンドでPNG変換処理を行う
            if !imagesData.isEmpty {
                let base64Images = await ChatInputImage.processImages(imagesData)
                await MainActor.run {
                    userMessage.images = base64Images
                    userMessage.isProcessingImages = false
                }
            }
            
            var apiMessages = executor.chatMessages.filter { $0.id != assistantMessageId }
            if chatSettings.isSystemPromptEnabled && !chatSettings.systemPrompt.isEmpty {
                let systemMessage = ChatMessage(role: "system", content: chatSettings.systemPrompt)
                apiMessages.insert(systemMessage, at: 0)
            }
            
            await streamAssistantResponse(for: assistantMessageId, with: apiMessages, model: model)
        }
    }
    
    // 過去リビジョン参照中でも、最新の完成版だけをアーカイブしてリトライ開始する
    private func retryMessage(for messageId: UUID, with messageToRetry: ChatMessage) {
        generalErrorMessage = nil
        guard let indexToRetry = executor.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("Retry failed: Message with ID \(messageId) not found.")
            return
        }
        
        // ユーザーメッセージのリトライの場合
        if executor.chatMessages[indexToRetry].role == "user" {
            // 編集されたユーザーメッセージを履歴の最後に移動
            let userMessage = executor.chatMessages.remove(at: indexToRetry)
            executor.chatMessages.append(userMessage)
            let scrollId = userMessage.id
            
            // ユーザーメッセージ以降のアシスタントメッセージを削除
            executor.chatMessages.removeAll(where: { (message: ChatMessage) -> Bool in
                guard let messageCreatedAt = message.createdAt,
                      let userMessageCreatedAt = userMessage.createdAt else { return false }
                return messageCreatedAt > userMessageCreatedAt && message.role == "assistant"
            })
            
            var apiMessages = executor.chatMessages
            if chatSettings.isSystemPromptEnabled && !chatSettings.systemPrompt.isEmpty {
                let systemMessage = ChatMessage(role: "system", content: chatSettings.systemPrompt)
                apiMessages.insert(systemMessage, at: 0)
            }
            
            let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
            placeholderMessage.revisions = []
            placeholderMessage.currentRevisionIndex = 0
            placeholderMessage.originalContent = ""
            placeholderMessage.latestContent = ""
            executor.chatMessages.append(placeholderMessage)
            let assistantMessageId = placeholderMessage.id
            
            guard let model = currentSelectedModel else {
                generalErrorMessage = "Please select a model first."
                return
            }
            
            executor.isChatStreaming = true
            scrollToMessageIDTrigger = scrollId
            Task { await streamAssistantResponse(for: assistantMessageId, with: apiMessages, model: model) }
            
        } else { // アシスタントメッセージのリトライの場合 (既存ロジック)
            guard indexToRetry == executor.chatMessages.count - 1 else {
                print("Retry failed: Message is not the last one.")
                return
            }
            guard !executor.chatMessages[indexToRetry].isStreaming else {
                print("Retry failed: Message is still streaming.")
                return
            }
            // 直前のユーザーメッセージまでをAPIに渡す
            guard indexToRetry > 0, executor.chatMessages[indexToRetry - 1].role == "user" else {
                print("Retry failed: User message not found immediately before assistant message at index \(indexToRetry).")
                return
            }
            let userMessageIndex = indexToRetry - 1
            let scrollId = executor.chatMessages[userMessageIndex].id
            
            // 1) 最新の完成版を厳密に選ぶ（参照中の状態に依存しない）
            // 本文は latestContent > content の順
            let latestCandidate = executor.chatMessages[indexToRetry].latestContent ?? ""
            let contentCandidate = executor.chatMessages[indexToRetry].content
            let archiveContent: String = {
                if !latestCandidate.isEmpty { return latestCandidate }
                return contentCandidate
            }()
            
            // Thinking は finalThinking > thinking > nil
            let finalThinkingCandidate = executor.chatMessages[indexToRetry].finalThinking
            let liveThinkingCandidate = executor.chatMessages[indexToRetry].thinking
            let archiveThinking: String? = {
                if let v = finalThinkingCandidate, !v.isEmpty { return v }
                if let v = liveThinkingCandidate, !v.isEmpty { return v }
                return nil
            }()
            
            // 2) 履歴アーカイブ（この関数内のみで1回）
            let archived = ChatMessage(
                role: executor.chatMessages[indexToRetry].role,
                content: archiveContent,
                thinking: archiveThinking,
                images: executor.chatMessages[indexToRetry].images,
                toolCalls: executor.chatMessages[indexToRetry].toolCalls,
                toolName: executor.chatMessages[indexToRetry].toolName,
                createdAt: executor.chatMessages[indexToRetry].createdAt,
                totalDuration: executor.chatMessages[indexToRetry].finalTotalDuration ?? executor.chatMessages[indexToRetry].totalDuration,
                evalCount: executor.chatMessages[indexToRetry].finalEvalCount ?? executor.chatMessages[indexToRetry].evalCount,
                evalDuration: executor.chatMessages[indexToRetry].finalEvalDuration ?? executor.chatMessages[indexToRetry].evalDuration,
                isStreaming: false,
                isStopped: executor.chatMessages[indexToRetry].finalIsStopped || executor.chatMessages[indexToRetry].isStopped,
                isThinkingCompleted: executor.chatMessages[indexToRetry].finalIsThinkingCompleted || executor.chatMessages[indexToRetry].isThinkingCompleted
            )
            archived.revisions = executor.chatMessages[indexToRetry].revisions
            archived.currentRevisionIndex = executor.chatMessages[indexToRetry].currentRevisionIndex
            archived.originalContent = executor.chatMessages[indexToRetry].originalContent
            archived.latestContent = executor.chatMessages[indexToRetry].latestContent
            archived.finalThinking = executor.chatMessages[indexToRetry].finalThinking
            archived.finalIsThinkingCompleted = executor.chatMessages[indexToRetry].finalIsThinkingCompleted
            archived.finalCreatedAt = executor.chatMessages[indexToRetry].finalCreatedAt ?? executor.chatMessages[indexToRetry].createdAt
            archived.finalTotalDuration = executor.chatMessages[indexToRetry].finalTotalDuration ?? executor.chatMessages[indexToRetry].totalDuration
            archived.finalEvalCount = executor.chatMessages[indexToRetry].finalEvalCount ?? executor.chatMessages[indexToRetry].evalCount
            archived.finalEvalDuration = executor.chatMessages[indexToRetry].finalEvalDuration ?? executor.chatMessages[indexToRetry].evalDuration
            archived.finalIsStopped = executor.chatMessages[indexToRetry].finalIsStopped || executor.chatMessages[indexToRetry].isStopped
            
            executor.chatMessages[indexToRetry].revisions.append(archived)
            // 参照位置は常に最新（末尾の次 = 現在バージョン）
            executor.chatMessages[indexToRetry].currentRevisionIndex = executor.chatMessages[indexToRetry].revisions.count
            
            // 3) 再実行準備
            executor.chatMessages[indexToRetry].content = ""
            executor.chatMessages[indexToRetry].thinking = nil
            executor.chatMessages[indexToRetry].isStreaming = true
            executor.chatMessages[indexToRetry].isStopped = false
            executor.chatMessages[indexToRetry].isThinkingCompleted = false
            executor.chatMessages[indexToRetry].createdAt = MessageView.iso8601Formatter.string(from: Date())
            executor.chatMessages[indexToRetry].totalDuration = nil
            executor.chatMessages[indexToRetry].evalCount = nil
            executor.chatMessages[indexToRetry].evalDuration = nil
            
            // 4) APIに出すメッセージ（ユーザー発話まで）
            var apiMessages = Array(executor.chatMessages.prefix(userMessageIndex + 1))
            if chatSettings.isSystemPromptEnabled && !chatSettings.systemPrompt.isEmpty {
                let systemMessage = ChatMessage(role: "system", content: chatSettings.systemPrompt)
                apiMessages.insert(systemMessage, at: 0)
            }
            
            guard let model = currentSelectedModel else {
                generalErrorMessage = "Please select a model first."
                return
            }
            
            executor.isChatStreaming = true
            scrollToMessageIDTrigger = scrollId
            Task { await streamAssistantResponse(for: messageId, with: apiMessages, model: model) }
        }
    }
    
    /// ストリーミング応答を処理し、UIの更新負荷に応じて動的に頻度と排出量を調整
    @MainActor
    private func streamAssistantResponse(for messageId: UUID, with apiMessages: [ChatMessage], model: OllamaModel) async {
        var isFirstChunk = true
        var isInsideThinkingBlock = false
        
        // --- 排出システムの管理用状態 ---
        class StreamBuffer {
            var rawContent = ""
            var rawThinking = ""
            var isThinkingCompleted = false
            var isStreamingFinished = false
            var finalChunk: ChatResponseChunk? = nil
        }
        
        let buffer = StreamBuffer()
        var displayedContentLength = 0
        var displayedThinkingLength = 0
        
        // --- ディスペンサー（排出）ループ ---
        let dispenserTask = Task {
#if os(visionOS)
            var currentInterval: TimeInterval = 0.066 // visionOSは15fpsから開始して負荷を抑制
#else
            var currentInterval: TimeInterval = 0.033 // 他は30fps
#endif
            var charsPerTick: Int = 30
            
            while true {
                if buffer.isStreamingFinished && 
                   buffer.rawContent.count <= displayedContentLength && 
                   buffer.rawThinking.count <= displayedThinkingLength {
                    break
                }
                
                let tickStart = Date()
                
                let lag = (buffer.rawContent.count - displayedContentLength) + (buffer.rawThinking.count - displayedThinkingLength)
                let adaptiveChars = charsPerTick + (lag > 200 ? (lag / 100) * 10 : 0)
                
                let targetC = min(buffer.rawContent.count, displayedContentLength + adaptiveChars)
                let targetT = min(buffer.rawThinking.count, displayedThinkingLength + adaptiveChars)
                
                let nextC = String(buffer.rawContent.prefix(targetC))
                let nextT = String(buffer.rawThinking.prefix(targetT))
                
                if let index = executor.chatMessages.firstIndex(where: { $0.id == messageId }) {
                    // プロパティ更新を一括化してObservationの通知回数を削減
                    executor.chatMessages[index].updateStreamingContent(
                        content: nextC,
                        thinking: nextT.isEmpty ? nil : nextT,
                        isThinkingCompleted: buffer.isThinkingCompleted
                    )
                    
                    displayedContentLength = targetC
                    displayedThinkingLength = targetT
                } else {
                    break
                }
                
                let tickEnd = Date()
                let updateDuration = tickEnd.timeIntervalSince(tickStart)
                
                // --- メインスレッド負荷に応じた適応的調整 ---
                if updateDuration > 0.016 {
                    currentInterval = min(0.25, currentInterval + 0.02)
                    charsPerTick = max(5, charsPerTick - 1)
                } else if updateDuration < 0.008 && lag > 0 {
                    currentInterval = max(0.01, currentInterval - 0.005)
                    charsPerTick = min(300, charsPerTick + 5)
                }
                
                try? await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
                if Task.isCancelled { break }
            }
            
            // 最終確定処理
            if let index = executor.chatMessages.firstIndex(where: { $0.id == messageId }), 
               let chunk = buffer.finalChunk {
                let isThinkingCompleted = buffer.isThinkingCompleted || !buffer.rawThinking.isEmpty
                
                executor.chatMessages[index].finalizeStreaming(
                    content: buffer.rawContent,
                    thinking: buffer.rawThinking.isEmpty ? nil : buffer.rawThinking,
                    totalDuration: chunk.totalDuration,
                    evalCount: chunk.evalCount,
                    evalDuration: chunk.evalDuration,
                    isThinkingCompleted: isThinkingCompleted
                )
                
                executor.chatMessages[index].finalThinking = executor.chatMessages[index].thinking
                executor.chatMessages[index].finalIsThinkingCompleted = executor.chatMessages[index].isThinkingCompleted
                executor.chatMessages[index].finalCreatedAt = executor.chatMessages[index].createdAt
                executor.chatMessages[index].finalTotalDuration = executor.chatMessages[index].totalDuration
                executor.chatMessages[index].finalEvalCount = executor.chatMessages[index].evalCount
                executor.chatMessages[index].finalEvalDuration = executor.chatMessages[index].evalDuration
                executor.chatMessages[index].finalIsStopped = executor.chatMessages[index].isStopped
            }
        }
        
        do {
            // パラメータの計算
            let repeatLastNValue: Int? = {
                switch chatSettings.repeatLastNOption {
                case .none: return nil
                case .disabled: return 0
                case .custom: return chatSettings.repeatLastNValue
                case .max: return -1
                }
            }()
            
            let numPredictValue: Int? = {
                switch chatSettings.numPredictOption {
                case .none: return nil
                case .custom: return chatSettings.numPredictValue
                case .unlimited: return -1
                }
            }()
            
            for try await chunk in executor.chat(
                model: model.name,
                messages: apiMessages,
                stream: chatSettings.isStreamingEnabled,
                useCustomChatSettings: chatSettings.useCustomChatSettings,
                isTemperatureEnabled: chatSettings.isTemperatureEnabled,
                chatTemperature: chatSettings.chatTemperature,
                isContextWindowEnabled: chatSettings.isContextWindowEnabled,
                contextWindowValue: chatSettings.contextWindowValue,
                isSeedEnabled: chatSettings.isSeedEnabled,
                seed: chatSettings.seed,
                repeatLastN: repeatLastNValue,
                repeatPenalty: chatSettings.isRepeatPenaltyEnabled ? chatSettings.repeatPenaltyValue : nil,
                numPredict: numPredictValue,
                topK: chatSettings.isTopKEnabled ? chatSettings.topKValue : nil,
                topP: chatSettings.isTopPEnabled ? chatSettings.topPValue : nil,
                minP: chatSettings.isMinPEnabled ? chatSettings.minPValue : nil,
                isSystemPromptEnabled: chatSettings.isSystemPromptEnabled,
                systemPrompt: chatSettings.systemPrompt,
                thinkingOption: chatSettings.thinkingOption,
                tools: nil,
                keepAlive: chatSettings.finalKeepAlive
            ) {
                guard let assistantMessageIndex = executor.chatMessages.firstIndex(where: { $0.id == messageId }) else { continue }
                
                if let messageChunk = chunk.message {
                    if chatSettings.thinkingOption == .on {
                        if let apiThinking = messageChunk.thinking { buffer.rawThinking += apiThinking }
                        if !messageChunk.content.isEmpty {
                            buffer.rawContent += messageChunk.content
                            buffer.isThinkingCompleted = true
                        }
                    } else {
                        var current = messageChunk.content
                        if let start = current.range(of: "<think>") {
                            isInsideThinkingBlock = true
                            buffer.rawContent += String(current[..<start.lowerBound])
                            current = String(current[start.upperBound...])
                        }
                        if let end = current.range(of: "</think>") {
                            isInsideThinkingBlock = false
                            buffer.rawThinking += String(current[..<end.lowerBound])
                            buffer.rawContent += String(current[end.upperBound...])
                            buffer.isThinkingCompleted = true
                        } else if isInsideThinkingBlock {
                            buffer.rawThinking += current
                        } else {
                            buffer.rawContent += current
                        }
                    }
                    
                    if isFirstChunk {
                        if executor.chatMessages.indices.contains(assistantMessageIndex) {
                            executor.chatMessages[assistantMessageIndex].createdAt = chunk.createdAt
                        }
                        // 最初のレスポンスが来た = モデルがメモリにロードされたので実行中リストを更新
                        Task {
                            await executor.fetchRunningModels()
                        }
                        isFirstChunk = false
                    }
                }
                
                if chunk.done {
                    buffer.isStreamingFinished = true
                    buffer.finalChunk = chunk
                }
            }
        } catch {
            print("Chat streaming error or cancelled: \(error)")
            dispenserTask.cancel()
            if let index = executor.chatMessages.firstIndex(where: { $0.id == messageId }), executor.chatMessages.indices.contains(index) {
                executor.chatMessages[index].isStreaming = false
                
                let isCancelled = (error as? URLError)?.code == .cancelled || 
                                 (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == -999
                
                if isCancelled {
                    executor.chatMessages[index].isStopped = true
                } else {
                    executor.chatMessages[index].isStopped = false
                    
                    var fullErrorMessage = "Chat API Error: \(error.localizedDescription)"
                    if (error as? URLError)?.code == .timedOut {
                        fullErrorMessage += "\n\n" + String(localized: "If it takes time to load large models, increasing the API timeout in Mocolamma settings or changing it to unlimited may help.")
                    }
                    
                    if executor.chatMessages[index].content.isEmpty {
                        executor.chatMessages[index].content = fullErrorMessage
                    }
                    
                    generalErrorMessage = fullErrorMessage
                }
            }
        }
        await dispenserTask.value
        executor.isChatStreaming = false
    }
}


struct ImageGenerationView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ServerManager.self) var serverManager
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    @Environment(ImageGenerationSettings.self) var imageSettings
    @Environment(\.requestReview) var requestReview
    private var modelSettings = ModelSettingsManager.shared
    @State private var selectionCoordinator = TextSelectionCoordinator()
    
    @State private var errorMessage: String?
    @State private var generalErrorMessage: String? = nil
    @State private var showingClearConfirm: Bool = false
    @State private var inputAreaHeight: CGFloat = 0
    @State private var isNearBottom: Bool = true
    @State private var scrollToBottomTrigger: Int = 0
    @State private var scrollToMessageIDTrigger: UUID? = nil
    
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
    
    init(showingInspector: Binding<Bool>, onToggleInspector: @escaping () -> Void) {
        self._showingInspector = showingInspector
        self.onToggleInspector = onToggleInspector
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var currentSelectedModel: OllamaModel? {
        if let id = imageSettings.selectedModelID {
            return executor.models.first(where: { $0.id == id })
        }
        return nil
    }
    
    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        @Bindable var executor = executor
        ZStack {
            if serverManager.selectedServer == nil {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "server.rack",
                    description: Text("Please select a server in the Server tab.")
                )
            } else if executor.apiConnectionError {
                ContentUnavailableView(
                    "Connection Failed",
                    systemImage: "network.slash",
                    description: Text(LocalizedStringKey(executor.specificConnectionErrorMessage ?? "Failed to connect to the Ollama API. Please check your network connection or server settings."))
                )
            } else {
                ChatMessagesView(
                    messages: $executor.imageMessages,
                    onRetry: retryGeneration,
                    isOverallStreaming: $executor.isImageStreaming,
                    isNearBottom: $isNearBottom,
                    scrollToBottomTrigger: $scrollToBottomTrigger,
                    scrollToMessageIDTrigger: $scrollToMessageIDTrigger,
                    isModelSelected: imageSettings.selectedModelID != nil,
                    bottomInset: inputAreaHeight,
                    emptyStateTitle: "Image Generation",
                    emptyStateDescription: "Here you can generate images using models that support image generation.",
                    emptyStateImage: "photo.stack.fill"
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func makeInputArea() -> some View {
        @Bindable var executor = executor
        VStack(spacing: 0) {
#if !os(visionOS)
            ScrollToBottomButton(isNearBottom: isNearBottom, messagesEmpty: executor.imageMessages.isEmpty, scrollToBottomTrigger: $scrollToBottomTrigger)
#endif
            
            ChatInputView(
                inputText: $executor.chatInputText,
                selectedImages: $executor.imageInputImages,
                isStreaming: $executor.isImageStreaming,
                showingInspector: $showingInspector,
                placeholder: "Enter a prompt...",
                selectedModel: currentSelectedModel
            ) {
                generateImage()
            } stopMessage: {
                if let last = executor.imageMessages.last, last.role == "assistant" && last.isStreaming {
                    last.isStreaming = false
                    last.isStopped = true
                }
                executor.isImageStreaming = false
                executor.cancelImageGeneration()
            }
        }
        .animation(.spring(duration: 0.3), value: executor.imageMessages.isEmpty)
#if !os(visionOS)
        .padding()
#endif
#if os(visionOS)
        .onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.height + 32) / 2
        } action: { newValue in
            inputAreaHeight = newValue
        }
#endif
    }
    
    var body: some View {
        @Bindable var executor = executor
        Group {
#if os(visionOS)
            ZStack(alignment: .bottom) {
                if #available(visionOS 26.0, *) {
                    content
                        .safeAreaBar(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                } else {
                    content
                        .safeAreaInset(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                }

                ZStack(alignment: .bottom) {
                    ScrollToBottomButton(isNearBottom: isNearBottom, messagesEmpty: executor.imageMessages.isEmpty, scrollToBottomTrigger: $scrollToBottomTrigger)
                        .padding(.bottom, inputAreaHeight + 8)
                }
                .animation(.spring(duration: 0.3), value: isNearBottom)
                .animation(.spring(duration: 0.3), value: executor.imageMessages.isEmpty)
            }
            .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
                makeInputArea()
                    .frame(width: 600)
                    .padding(16)
                    .glassBackgroundEffect()
            }
#elseif os(iOS)
            if #available(iOS 26.0, *) {
                content
                    .safeAreaBar(edge: .bottom) {
                        makeInputArea()
                    }
            } else {
                content
                    .safeAreaInset(edge: .bottom) {
                        makeInputArea()
                    }
            }
#else
            if #available(macOS 26.0, *) {
                content
                    .safeAreaBar(edge: .bottom) {
                        makeInputArea()
                    }
            } else {
                content
                    .safeAreaInset(edge: .bottom) {
                        makeInputArea()
                    }
            }
#endif
        }
#if !os(macOS)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            selectionCoordinator.deselectAll()
        }
#endif
        .environment(selectionCoordinator)
        .modifier(TextSelectionCoordination())
        .navigationTitle("Image Generation")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear {
            if let current = imageSettings.selectedModelID, !executor.models.contains(where: { $0.id == current }) {
                imageSettings.selectedModelID = nil
            }
        }
        .onDrop(of: [.fileURL, .image], delegate: AreaImageDropDelegate(items: .constant([]), isDraggingOver: .constant(false), executor: executor, isEnabled: currentSelectedModel?.supportsVision ?? false))
        .task {
            // サーバーが選択されており、かつ初期フェッチが未完了の場合のみ自動リフレッシュを実行
            // これにより、タブ切り替えのたびにリロードが走るのを防ぎ、ハングアップを回避する
            if serverManager.selectedServer != nil && !executor.initialFetchCompleted && !executor.isRunning && !executor.isPulling {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    appRefreshTrigger.send()
                }
            }
        }
        .onChange(of: executor.models) { _, newModels in
            if let currentSelectedModelID = imageSettings.selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
                imageSettings.selectedModelID = nil
            }
        }
        .alert(Text("Error Occurred"), isPresented: Binding<Bool>(
            get: { generalErrorMessage != nil },
            set: { if !$0 { generalErrorMessage = nil } }
        )) {
            Button("OK") { generalErrorMessage = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            if let errorMessage = generalErrorMessage {
                Text(errorMessage)
            } else {
                Text("An unknown error occurred.")
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var imageSettings = imageSettings
        @Bindable var executor = executor
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling)
        }
        
        ToolbarItem(placement: .primaryAction) {
            Picker("Select Model", selection: $imageSettings.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                let sortedModels = executor.models.filter { $0.isImageModel }.sorted(using: modelSettings.sortOrder(forChat: false))
                ForEach(sortedModels) { model in
                    let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                    HStack {
                        Text(model.name)
                        if isRunning { Image(systemName: "tray.and.arrow.down") }
                    }
                    .tag(model.id as OllamaModel.ID?)
                }
                if executor.models.filter({ $0.isImageModel }).isEmpty {
                    Divider()
                    if executor.isRunning {
                        Text("Loading models...")
                            .tag("loading-image-models-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    } else {
                        Text("No models available")
                            .tag("no-image-models-available-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
#else
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling)
            
            Menu {
                Section {
                    Picker("Select Model", selection: $imageSettings.selectedModelID) {
                        Text("Select Model").tag(nil as OllamaModel.ID?)
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Picker("Models", selection: $imageSettings.selectedModelID) {
                        let sortedModels = executor.models.filter { $0.isImageModel }.sorted(using: modelSettings.sortOrder(forChat: false))
                        ForEach(sortedModels) { model in
                            let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                            HStack {
                                Text(model.name)
                                if isRunning { Image(systemName: "tray.and.arrow.down") }
                            }
                            .tag(model.id as OllamaModel.ID?)
                        }
                    }
                    .pickerStyle(.inline)
                }
                if executor.models.filter({ $0.isImageModel }).isEmpty {
                    Section {
                        if executor.isRunning {
                            Button(action: {}) { Text("Loading models...") }.disabled(true)
                        } else {
                            Button(action: {}) { Text("No models available") }.disabled(true)
                        }
                    }
                }
            } label: {
                let selectedModelName = executor.models.first(where: { $0.id == imageSettings.selectedModelID })?.name
                Label(selectedModelName ?? String(localized: "Select Model"), systemImage: imageSettings.selectedModelID != nil ? "tray.full.fill" : "tray.full")
#if os(visionOS)
                    .labelStyle(.titleAndIcon)
#endif
            }
            .help({
                if let selectedModelName = executor.models.first(where: { $0.id == imageSettings.selectedModelID })?.name {
                    return String(format: NSLocalizedString("Select Model (%@ Selected)", comment: "モデルが選択されている時のツールチップ。"), selectedModelName)
                }
                return String(localized: "Select Model")
            }())
        }
#endif

#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif

        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !executor.imageMessages.isEmpty { showingClearConfirm = true }
            }) {
                Label("New Generation", systemImage: "square.and.pencil")
            }
            .disabled(executor.imageMessages.isEmpty)
            .confirmationDialog(String(localized: "Are you sure you want to clear the generation history?"), isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button(String(localized: "Clear History"), role: .destructive) {
                    executor.clearImageGeneration()
                    executor.chatInputText = ""
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }

#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif

#if !os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: (isNativeVisionOS || isiOSAppOnVision) ? "info.circle" : (horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing"))
            }
        }
#endif
    }
    
    private func generateImage() {
        ReviewManager.shared.requestReviewIfAppropriate(requestReviewAction: requestReview)

        guard let model = currentSelectedModel else {
            generalErrorMessage = "Please select a model first."
            return
        }

        guard !executor.chatInputText.isEmpty || !executor.imageInputImages.isEmpty else { return }
        
        let prompt = executor.chatInputText
        executor.chatInputText = ""
        executor.imageInputImages = []
        executor.isImageStreaming = true
        
        let userMessage = ChatMessage(role: "user", content: prompt, createdAt: MessageView.iso8601Formatter.string(from: Date()))
        executor.imageMessages.append(userMessage)
        
        let assistantMessage = ChatMessage(
            role: "assistant",
            content: "",
            createdAt: MessageView.iso8601Formatter.string(from: Date()),
            isStreaming: true,
            isImageGeneration: true
        )
        executor.imageMessages.append(assistantMessage)
        let assistantMessageId = assistantMessage.id
        
        Task {
            await runImageGeneration(for: assistantMessageId, prompt: prompt, model: model)
        }
    }
    
    private func retryGeneration(for messageId: UUID, with messageToRetry: ChatMessage) {
        // 画像生成のリトライロジック
        guard let index = executor.imageMessages.firstIndex(where: { $0.id == messageId }) else { return }
        
        let promptId: UUID
        let prompt: String
        if executor.imageMessages[index].role == "user" {
            promptId = executor.imageMessages[index].id
            prompt = executor.imageMessages[index].content
            executor.imageMessages.removeSubrange(index+1..<executor.imageMessages.count)
        } else {
            guard index > 0 else { return }
            promptId = executor.imageMessages[index-1].id
            prompt = executor.imageMessages[index-1].content
            
            // 重要: 現在表示中のリビジョンではなく、常に「最新の完成版」をアーカイブする
            let archiveContent: String = {
                if let latest = executor.imageMessages[index].latestContent, !latest.isEmpty { return latest }
                return executor.imageMessages[index].content
            }()
            let archiveImage = executor.imageMessages[index].latestGeneratedImage ?? executor.imageMessages[index].generatedImage
            let archiveCreatedAt = executor.imageMessages[index].finalCreatedAt ?? executor.imageMessages[index].createdAt
            let archiveTotalDuration = executor.imageMessages[index].finalTotalDuration ?? executor.imageMessages[index].totalDuration
            let archiveIsStopped = executor.imageMessages[index].finalIsStopped || executor.imageMessages[index].isStopped
            
            let archived = ChatMessage(
                role: "assistant",
                content: archiveContent,
                createdAt: archiveCreatedAt,
                totalDuration: archiveTotalDuration,
                isStreaming: false,
                isStopped: archiveIsStopped,
                generatedImage: archiveImage,
                isImageGeneration: true
            )
            executor.imageMessages[index].revisions.append(archived)
            // 参照位置は常に最新（末尾の次 = 現在バージョン）にする
            executor.imageMessages[index].currentRevisionIndex = executor.imageMessages[index].revisions.count
            
            // 再初期化
            executor.imageMessages[index].generatedImage = nil
            executor.imageMessages[index].latestGeneratedImage = nil
            executor.imageMessages[index].imageProgressCompleted = nil
            executor.imageMessages[index].imageProgressTotal = nil
            executor.imageMessages[index].isStreaming = true
            executor.imageMessages[index].isStopped = false
            executor.imageMessages[index].totalDuration = nil
            executor.imageMessages[index].finalTotalDuration = nil
            executor.imageMessages[index].finalCreatedAt = nil
        }
        
        guard let model = currentSelectedModel else { return }
        executor.isImageStreaming = true
        
        if executor.imageMessages[index].role == "user" {
            let assistantMessage = ChatMessage(
                role: "assistant",
                content: "",
                createdAt: MessageView.iso8601Formatter.string(from: Date()),
                isStreaming: true,
                isImageGeneration: true
            )
            executor.imageMessages.append(assistantMessage)
            scrollToMessageIDTrigger = promptId
            Task { await runImageGeneration(for: assistantMessage.id, prompt: prompt, model: model) }
        } else {
            scrollToMessageIDTrigger = promptId
            Task { await runImageGeneration(for: messageId, prompt: prompt, model: model) }
        }
    }
    
    private func runImageGeneration(for messageId: UUID, prompt: String, model: OllamaModel) async {
        do {
            for try await chunk in executor.generateImage(
                model: model.name,
                prompt: prompt,
                stream: imageSettings.isStreamingEnabled,
                width: imageSettings.finalWidth,
                height: imageSettings.finalHeight,
                steps: imageSettings.finalSteps,
                seed: imageSettings.isSeedEnabled ? imageSettings.seed : nil,
                keepAlive: imageSettings.finalKeepAlive
            ) {
                guard let index = executor.imageMessages.firstIndex(where: { $0.id == messageId }) else { break }
                
                // 最初のチャンク処理（またはループ開始時）に実行中モデルリストを更新
                if chunk.completed == 1 || chunk.completed == nil {
                    Task {
                        await executor.fetchRunningModels()
                    }
                }
                
                await MainActor.run {
                    if let completed = chunk.completed {
                        executor.imageMessages[index].imageProgressCompleted = completed
                    }
                    if let total = chunk.total {
                        executor.imageMessages[index].imageProgressTotal = total
                    }
                    if let img = chunk.image {
                        executor.imageMessages[index].generatedImage = img
                    }
                    if let createdAt = chunk.createdAt {
                        executor.imageMessages[index].createdAt = createdAt
                    }
                    
                    if chunk.done {
                        executor.imageMessages[index].isStreaming = false
                        executor.imageMessages[index].totalDuration = chunk.totalDuration
                        executor.imageMessages[index].finalTotalDuration = chunk.totalDuration
                        executor.imageMessages[index].finalCreatedAt = executor.imageMessages[index].createdAt
                        executor.imageMessages[index].latestGeneratedImage = executor.imageMessages[index].generatedImage
                    }
                }
            }
        } catch {
            print("Image generation error: \(error)")
            if let index = executor.imageMessages.firstIndex(where: { $0.id == messageId }) {
                await MainActor.run {
                    executor.imageMessages[index].isStreaming = false
                    
                    let isCancelled = (error as? URLError)?.code == .cancelled || 
                                     (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == -999
                    
                    if isCancelled {
                        executor.imageMessages[index].isStopped = true
                        if executor.imageMessages[index].generatedImage == nil {
                            executor.imageMessages[index].content = "*Cancelled*"
                        }
                    } else {
                        executor.imageMessages[index].isStopped = false
                        if executor.imageMessages[index].generatedImage == nil {
                            executor.imageMessages[index].content = "Error: \(error.localizedDescription)"
                        }
                        
                        var fullErrorMessage = "Image Generation Error: \(error.localizedDescription)"
                        if (error as? URLError)?.code == .timedOut {
                            fullErrorMessage += "\n\n" + String(localized: "If it takes time to load large models, increasing the API timeout in Mocolamma settings or changing it to unlimited may help.")
                        }
                        generalErrorMessage = fullErrorMessage
                    }
                }
            }
        }
        await MainActor.run { 
            executor.isImageStreaming = false 
            executor.updateIsImageStreaming()
        }
    }
}

struct ScrollToBottomButton: View {
    let isNearBottom: Bool
    let messagesEmpty: Bool
    @Binding var scrollToBottomTrigger: Int

    var body: some View {
        if !isNearBottom && !messagesEmpty {
            Button {
                scrollToBottomTrigger += 1
            } label: {
                Label(String(localized: "Scroll to Bottom", comment: "Button text to scroll to the bottom of the chat or image generation view."), systemImage: "arrow.down.to.line.compact")
                    .font(.subheadline.bold())
                    .padding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
