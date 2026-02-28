import SwiftUI
import Textual
import ImageIO
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(CommandExecutor.self) var executor
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @EnvironmentObject var chatSettings: ChatSettings
    
    @State private var errorMessage: String?
    @State private var showUnsupportedModelAlert: Bool = false
    @State private var generalErrorMessage: String? = nil
    @State private var showingNewChatConfirm: Bool = false
    
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
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
                // OSバージョン26以降かどうかの条件分岐
                if #available(iOS 26.0, macOS 26.0, *) {
                    ChatMessagesView(messages: $executor.chatMessages, onRetry: retryMessage, isOverallStreaming: $executor.isChatStreaming, isModelSelected: chatSettings.selectedModelID != nil, isUsingSafeAreaBar: true, emptyStateTitle: "Chat", emptyStateDescription: "Here you can perform a simple chat to check the model.", emptyStateImage: "message.fill")
                } else {
                    ChatMessagesView(messages: $executor.chatMessages, onRetry: retryMessage, isOverallStreaming: $executor.isChatStreaming, isModelSelected: chatSettings.selectedModelID != nil, isUsingSafeAreaBar: false, emptyStateTitle: "Chat", emptyStateDescription: "Here you can perform a simple chat to check the model.", emptyStateImage: "message.fill")
                }
            }
        }
        .frame(maxHeight: .infinity) // Make sure it fills the available height
    }
    
    @ViewBuilder
    private func makeSafeAreaBarContent() -> some View {
        @Bindable var executor = executor
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
        .padding()
    }
    
    var body: some View {
        @Bindable var executor = executor
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                chatContent
                    .safeAreaBar(edge: .bottom) {
                        makeSafeAreaBarContent()
                    }
            } else {
                ZStack {
                    chatContent
                    
                    VStack {
                        Spacer()
                        
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
                    .padding()
                    .if(horizontalSizeClass != .compact) { view in
                        view.ignoresSafeArea(.container, edges: [.bottom])
                    }
                }
            }
        }
#if os(iOS)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
#endif
        .navigationTitle("Chat")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear {
            if let current = chatSettings.selectedModelID, !executor.models.contains(where: { $0.id == current }) {
                chatSettings.selectedModelID = nil
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                appRefreshTrigger.send()
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
#if os(iOS)
        ToolbarItemGroup(placement: .primaryAction) { // リフレッシュとモデル選択のグループ (iOS)
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
            
            Menu {
                Picker("Select Model", selection: $chatSettings.selectedModelID) {
                    Text("Select Model").tag(nil as OllamaModel.ID?)
                    ForEach(executor.models.filter { $0.supportsCompletion }) { model in
                        let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                        HStack {
                            Text(model.name)
                            if isRunning {
                                Image(systemName: "tray.and.arrow.down")
                            }
                        }
                        .tag(model.id as OllamaModel.ID?)
                    }
                    if executor.models.filter({ $0.supportsCompletion }).isEmpty {
                        Divider()
                        Text(LocalizedStringKey("No models available"))
                            .tag("no-models-available-tag" as OllamaModel.ID?) // ユニークでnilでない文字列を割り当てる
                            .selectionDisabled(true)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: chatSettings.selectedModelID != nil ? "tray.full.fill" : "tray.full")
            }
        }
#else // macOS
        ToolbarItem(placement: .primaryAction) { // リフレッシュボタン（macOS）
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
        }
        ToolbarItem(placement: .primaryAction) { // モデルピッカー (macOS)
            Picker("Select Model", selection: $chatSettings.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                ForEach(executor.models.filter { $0.supportsCompletion }) { model in
                    let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                    HStack {
                        Text(model.name)
                        if isRunning {
                            Image(systemName: "tray.and.arrow.down")
                        }
                    }
                    .tag(model.id as OllamaModel.ID?)
                }
                if executor.models.filter({ $0.supportsCompletion }).isEmpty {
                    Divider()
                    Text(LocalizedStringKey("No models available"))
                        .tag("no-models-available-tag" as OllamaModel.ID?) // ユニークでnilでない文字列を割り当てる
                        .selectionDisabled(true)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
        }
#endif
        
#if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // モデルグループと新規チャットの間のスペーサー
        }
#endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !executor.chatMessages.isEmpty {
                    showingNewChatConfirm = true
                }
            }) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .disabled(executor.chatMessages.isEmpty)
            .confirmationDialog(
                String(localized: "Are you sure you want to clear the chat history?"),
                isPresented: $showingNewChatConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Clear Chat History"), role: .destructive) {
                    executor.clearChat()
                    executor.isChatStreaming = false
                    errorMessage = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }
        
#if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // 新規チャットとインスペクターの間のスペーサー
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing")
            }
        }
#endif
    }
    
    private func sendMessage() {
        generalErrorMessage = nil
        guard let model = currentSelectedModel else {
            generalErrorMessage = "Please select a model first."
            return
        }
        guard !executor.chatInputText.isEmpty || !executor.chatInputImages.isEmpty else { return }
        
        let text = executor.chatInputText
        let imagesData = executor.chatInputImages
        executor.chatInputText = ""
        executor.chatInputImages = []
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
                let base64Images = await processImagesInBackground(imagesData)
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
    
    private func processImagesInBackground(_ imagesData: [Data]) async -> [String] {
        return await Task.detached(priority: .medium) {
            var results: [String] = []
            for data in imagesData {
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: false
                ]
                guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { continue }
                
                // 回転情報を反映し、かつ最大解像度を2048pxに制限して処理を高速化
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, // これで回転が修正されます
                    kCGImageSourceThumbnailMaxPixelSize: 2048 // 2048pxにリサイズして負荷を軽減
                ]
                
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                    continue
                }
                
                let outputData = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(outputData, UTType.png.identifier as CFString, 1, nil) else {
                    continue
                }
                
                CGImageDestinationAddImage(destination, cgImage, nil)
                if CGImageDestinationFinalize(destination) {
                    // リサイズ済みのデータからBase64文字列を生成（非常に高速になります）
                    results.append((outputData as Data).base64EncodedString())
                }
            }
            return results
        }.value
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
            Task { await streamAssistantResponse(for: messageId, with: apiMessages, model: model) }
        }
    }
    
    /// ストリーミング応答を処理し、UIをバッファリングしながら更新
    private func streamAssistantResponse(for messageId: UUID, with apiMessages: [ChatMessage], model: OllamaModel) async {
        var lastUIUpdateTime = Date()
        let throttleInterval = 0.03 // 約30fpsで更新
        var isFirstChunk = true
        var isInsideThinkingBlock = false
        
        var fullContent = ""
        var fullThinking = ""
        
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
                        if let apiThinking = messageChunk.thinking { fullThinking += apiThinking }
                        fullContent += messageChunk.content
                    } else {
                        var current = messageChunk.content
                        if let start = current.range(of: "<think>") {
                            isInsideThinkingBlock = true
                            fullContent += String(current[..<start.lowerBound])
                            current = String(current[start.upperBound...])
                        }
                        if let end = current.range(of: "</think>") {
                            isInsideThinkingBlock = false
                            fullThinking += String(current[..<end.lowerBound])
                            fullContent += String(current[end.upperBound...])
                            await MainActor.run {
                                if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                    executor.chatMessages[assistantMessageIndex].isThinkingCompleted = true
                                }
                            }
                        } else if isInsideThinkingBlock {
                            fullThinking += current
                        } else {
                            fullContent += current
                        }
                    }
                    
                    if isFirstChunk {
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                executor.chatMessages[assistantMessageIndex].createdAt = chunk.createdAt
                            }
                        }
                        // 最初のレスポンスが来た = モデルがメモリにロードされたので実行中リストを更新
                        Task {
                            await executor.fetchRunningModels()
                        }
                        isFirstChunk = false
                    }
                    
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) > throttleInterval || chunk.done {
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                // プロパティを直接更新して即座にMarkdownに反映
                                executor.chatMessages[assistantMessageIndex].content = fullContent
                                executor.chatMessages[assistantMessageIndex].thinking = fullThinking.isEmpty ? nil : fullThinking
                                
                                executor.chatMessages[assistantMessageIndex].latestContent = fullContent
                                
                                if chatSettings.thinkingOption == .on &&
                                    !fullThinking.isEmpty &&
                                    !fullContent.isEmpty &&
                                    !executor.chatMessages[assistantMessageIndex].isThinkingCompleted {
                                    executor.chatMessages[assistantMessageIndex].isThinkingCompleted = true
                                }
                            }
                        }
                        lastUIUpdateTime = now
                    }
                }
                
                if chunk.done {
                    if let index = executor.chatMessages.firstIndex(where: { $0.id == messageId }), executor.chatMessages.indices.contains(index) {
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(index) {
                                executor.chatMessages[index].content = fullContent
                                executor.chatMessages[index].thinking = fullThinking.isEmpty ? nil : fullThinking
                                executor.chatMessages[index].totalDuration = chunk.totalDuration
                                executor.chatMessages[index].evalCount = chunk.evalCount
                                executor.chatMessages[index].evalDuration = chunk.evalDuration
                                executor.chatMessages[index].isStreaming = false
                                
                                if chatSettings.thinkingOption == .on && executor.chatMessages[index].thinking != nil && !executor.chatMessages[index].isThinkingCompleted {
                                    executor.chatMessages[index].isThinkingCompleted = true
                                }
                                
                                executor.chatMessages[index].finalThinking = executor.chatMessages[index].thinking
                                executor.chatMessages[index].finalIsThinkingCompleted = executor.chatMessages[index].isThinkingCompleted
                                executor.chatMessages[index].finalCreatedAt = executor.chatMessages[index].createdAt
                                executor.chatMessages[index].finalTotalDuration = executor.chatMessages[index].totalDuration
                                executor.chatMessages[index].finalEvalCount = executor.chatMessages[index].evalCount
                                executor.chatMessages[index].finalEvalDuration = executor.chatMessages[index].evalDuration
                                executor.chatMessages[index].finalIsStopped = executor.chatMessages[index].isStopped
                            }
                        }
                    }
                }
            }
        } catch {
            print("Chat streaming error or cancelled: \(error)")
            if let index = executor.chatMessages.firstIndex(where: { $0.id == messageId }), executor.chatMessages.indices.contains(index) {
                await MainActor.run {
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
        }
        await MainActor.run { executor.isChatStreaming = false }
    }
}

struct ImageGenerationView: View {
    @Environment(CommandExecutor.self) var executor
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @EnvironmentObject var imageSettings: ImageGenerationSettings
    
    @State private var errorMessage: String?
    @State private var generalErrorMessage: String? = nil
    @State private var showingClearConfirm: Bool = false
    
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
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
                    isModelSelected: imageSettings.selectedModelID != nil,
                    isUsingSafeAreaBar: {
                        if #available(iOS 26.0, macOS 26.0, *) { return true }
                        return false
                    }(),
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
        .padding()
    }
    
    var body: some View {
        @Bindable var executor = executor
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                content
                    .safeAreaBar(edge: .bottom) {
                        makeInputArea()
                    }
            } else {
                ZStack {
                    content
                    
                    VStack {
                        Spacer()
                        makeInputArea()
                    }
                }
            }
        }
#if os(iOS)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
#endif
        .navigationTitle("Image Generation")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear {
            if let current = imageSettings.selectedModelID, !executor.models.contains(where: { $0.id == current }) {
                imageSettings.selectedModelID = nil
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                appRefreshTrigger.send()
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
#if os(iOS)
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
            
            Menu {
                Picker("Select Model", selection: $imageSettings.selectedModelID) {
                    Text("Select Model").tag(nil as OllamaModel.ID?)
                    ForEach(executor.models.filter { $0.isImageModel }) { model in
                        let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                        HStack {
                            Text(model.name)
                            if isRunning {
                                Image(systemName: "tray.and.arrow.down")
                            }
                        }
                        .tag(model.id as OllamaModel.ID?)
                    }
                    if executor.models.filter({ $0.isImageModel }).isEmpty {
                        Divider()
                        Text(LocalizedStringKey("No models available"))
                            .tag("no-image-models-available-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: imageSettings.selectedModelID != nil ? "tray.full.fill" : "tray.full")
            }
        }
#else
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Select Model", selection: $imageSettings.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                ForEach(executor.models.filter { $0.isImageModel }) { model in
                    let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                    HStack {
                        Text(model.name)
                        if isRunning {
                            Image(systemName: "tray.and.arrow.down")
                        }
                    }
                    .tag(model.id as OllamaModel.ID?)
                }
                if executor.models.filter({ $0.isImageModel }).isEmpty {
                    Divider()
                    Text(LocalizedStringKey("No models available"))
                        .tag("no-image-models-available-tag" as OllamaModel.ID?)
                        .selectionDisabled(true)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
        }
#endif
        
#if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // モデルグループと新規生成の間のスペーサー
        }
#endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !executor.imageMessages.isEmpty {
                    showingClearConfirm = true
                }
            }) {
                Label("New Generation", systemImage: "square.and.pencil")
            }
            .disabled(executor.imageMessages.isEmpty)
            .confirmationDialog(
                String(localized: "Are you sure you want to clear the generation history?"),
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Clear History"), role: .destructive) {
                    executor.clearImageGeneration()
                    executor.chatInputText = ""
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }
        
#if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // 新規生成とインスペクターの間のスペーサー
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing")
            }
        }
#endif
    }
    
    private func generateImage() {
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
        
        let prompt: String
        if executor.imageMessages[index].role == "user" {
            prompt = executor.imageMessages[index].content
            executor.imageMessages.removeSubrange(index+1..<executor.imageMessages.count)
        } else {
            guard index > 0 else { return }
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
            Task { await runImageGeneration(for: assistantMessage.id, prompt: prompt, model: model) }
        } else {
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
