import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
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
            } else if executor.chatMessages.isEmpty {
                ContentUnavailableView {
                    Label("Chat", systemImage: "message.fill")
                } description: {
                    Text("Here you can perform a simple chat to check the model.")
                }
            } else {
                // OSバージョン26以降かどうかの条件分岐
                if #available(iOS 26.0, macOS 26.0, *) {
                    ChatMessagesView(messages: $executor.chatMessages, onRetry: retryMessage, isOverallStreaming: $executor.isChatStreaming, isModelSelected: chatSettings.selectedModelID != nil, isUsingSafeAreaBar: true)
                } else {
                    ChatMessagesView(messages: $executor.chatMessages, onRetry: retryMessage, isOverallStreaming: $executor.isChatStreaming, isModelSelected: chatSettings.selectedModelID != nil, isUsingSafeAreaBar: false)
                }
            }        }
        .frame(maxHeight: .infinity) // Make sure it fills the available height
    }
    
    @ViewBuilder
    private func makeSafeAreaBarContent() -> some View {
        ChatInputView(inputText: $executor.chatInputText, isStreaming: $executor.isChatStreaming, showingInspector: $showingInspector, placeholder: "Type your message...", selectedModel: currentSelectedModel) {
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
                        
                        ChatInputView(inputText: $executor.chatInputText, isStreaming: $executor.isChatStreaming, showingInspector: $showingInspector, placeholder: "Type your message...", selectedModel: currentSelectedModel) {
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
        .onChange(of: chatSettings.selectedModelID) { _, newID in
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
        .alert("This model cannot be used", isPresented: $showUnsupportedModelAlert) {
            Button("OK") { showUnsupportedModelAlert = false }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(localized: "This model does not support chat.", comment: "ユーザがチャットに埋め込み専用モデルを使用しようとしたときのエラーメッセージ。"))
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { generalErrorMessage != nil },
            set: { if !$0 { generalErrorMessage = nil } }
        )) {
            Button("OK") { generalErrorMessage = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(generalErrorMessage ?? "An unknown error occurred.")
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
                    ForEach(executor.models) { model in
                        Text(model.name).tag(model.id as OllamaModel.ID?)
                    }
                    if executor.models.isEmpty {
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
                ForEach(executor.models) { model in
                    Text(model.name).tag(model.id as OllamaModel.ID?)
                }
                if executor.models.isEmpty {
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
        guard let model = currentSelectedModel else {
            generalErrorMessage = "Please select a model first."
            return
        }
        guard !executor.chatInputText.isEmpty else { return }
        
        executor.isChatStreaming = true
        let userMessage = ChatMessage(role: "user", content: executor.chatInputText, createdAt: MessageView.iso8601Formatter.string(from: Date()))
        executor.chatInputText = ""
        executor.chatMessages.append(userMessage)
        
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
        placeholderMessage.fixedContent = ""
        placeholderMessage.pendingContent = ""
        placeholderMessage.fixedThinking = ""
        placeholderMessage.pendingThinking = ""
        executor.chatMessages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id
        
        Task {
            await streamAssistantResponse(for: assistantMessageId, with: apiMessages, model: model)
        }
    }
    
    // 過去リビジョン参照中でも、最新の完成版だけをアーカイブしてリトライ開始する
    private func retryMessage(for messageId: UUID, with messageToRetry: ChatMessage) {
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
            placeholderMessage.fixedContent = ""
            placeholderMessage.pendingContent = ""
            placeholderMessage.fixedThinking = ""
            placeholderMessage.pendingThinking = ""
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
            // 本文は latestContent > content > fixed+pending の順
            let latestCandidate = executor.chatMessages[indexToRetry].latestContent ?? ""
            let contentCandidate = executor.chatMessages[indexToRetry].content
            let bufferedCandidate = executor.chatMessages[indexToRetry].fixedContent + executor.chatMessages[indexToRetry].pendingContent
            let archiveContent: String = {
                if !latestCandidate.isEmpty { return latestCandidate }
                if !contentCandidate.isEmpty { return contentCandidate }
                return bufferedCandidate
            }()
            
            // Thinking は finalThinking > thinking > fixed+pending > nil
            let finalThinkingCandidate = executor.chatMessages[indexToRetry].finalThinking
            let liveThinkingCandidate = executor.chatMessages[indexToRetry].thinking
            let bufferedThinkingCandidate = executor.chatMessages[indexToRetry].fixedThinking + executor.chatMessages[indexToRetry].pendingThinking
            let archiveThinking: String? = {
                if let v = finalThinkingCandidate, !v.isEmpty { return v }
                if let v = liveThinkingCandidate, !v.isEmpty { return v }
                if !bufferedThinkingCandidate.isEmpty { return bufferedThinkingCandidate }
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
            
            // 3) 再実行準備（表示バッファも初期化）
            executor.chatMessages[indexToRetry].content = ""
            executor.chatMessages[indexToRetry].thinking = nil
            executor.chatMessages[indexToRetry].fixedContent = ""
            executor.chatMessages[indexToRetry].pendingContent = ""
            executor.chatMessages[indexToRetry].fixedThinking = ""
            executor.chatMessages[indexToRetry].pendingThinking = ""
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
    
    /// ストリーミング応答を処理し、UIをバッファリングしながら更新（固定Markdown + 差分折り返しテキスト）
    private func streamAssistantResponse(for messageId: UUID, with apiMessages: [ChatMessage], model: OllamaModel) async {
        var lastUIUpdateTime = Date()
        let throttleInterval = 0.08
        var isFirstChunk = true
        var isInsideThinkingBlock = false
        
        var pendingMain = ""
        var pendingThinking = ""
        
        let flushCharThreshold = 300
        let flushNewlinePreferred = true
        
        func flushPendingToFixed(index: Int, force: Bool = false) async {
            guard executor.chatMessages.indices.contains(index) else { return }
            if force || pendingMain.count >= flushCharThreshold || (flushNewlinePreferred && pendingMain.contains("\n")) {
                let toAppend = pendingMain
                pendingMain.removeAll(keepingCapacity: true)
                let base = executor.chatMessages[index].fixedContent
                let newFixed = base + toAppend
                await MainActor.run {
                    if executor.chatMessages.indices.contains(index) { executor.chatMessages[index].fixedContent = newFixed }
                }
            }
            if force || pendingThinking.count >= flushCharThreshold || (flushNewlinePreferred && pendingThinking.contains("\n")) {
                let toAppend = pendingThinking
                pendingThinking.removeAll(keepingCapacity: true)
                let base = executor.chatMessages[index].fixedThinking
                let newFixed = base + toAppend
                await MainActor.run {
                    if executor.chatMessages.indices.contains(index) { executor.chatMessages[index].fixedThinking = newFixed }
                }
            }
        }
        
        do {
            for try await chunk in executor.chat(
                model: model.name,
                messages: apiMessages,
                stream: chatSettings.isStreamingEnabled,
                useCustomChatSettings: chatSettings.useCustomChatSettings,
                isTemperatureEnabled: chatSettings.isTemperatureEnabled,
                chatTemperature: chatSettings.chatTemperature,
                isContextWindowEnabled: chatSettings.isContextWindowEnabled,
                contextWindowValue: chatSettings.contextWindowValue,
                isSystemPromptEnabled: chatSettings.isSystemPromptEnabled,
                systemPrompt: chatSettings.systemPrompt,
                thinkingOption: chatSettings.thinkingOption,
                tools: nil
            ) {
                guard let assistantMessageIndex = executor.chatMessages.firstIndex(where: { $0.id == messageId }) else { continue }
                
                if let messageChunk = chunk.message {
                    if chatSettings.thinkingOption == .on {
                        if let apiThinking = messageChunk.thinking { pendingThinking += apiThinking }
                        pendingMain += messageChunk.content
                    } else {
                        var current = messageChunk.content
                        if let start = current.range(of: "<think>") {
                            isInsideThinkingBlock = true
                            pendingMain += String(current[..<start.lowerBound])
                            current = String(current[start.upperBound...])
                        }
                        if let end = current.range(of: "</think>") {
                            isInsideThinkingBlock = false
                            pendingThinking += String(current[..<end.lowerBound])
                            pendingMain += String(current[end.upperBound...])
                            await MainActor.run {
                                if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                    executor.chatMessages[assistantMessageIndex].isThinkingCompleted = true
                                }
                            }
                        } else if isInsideThinkingBlock {
                            pendingThinking += current
                        } else {
                            pendingMain += current
                        }
                    }
                    
                    if isFirstChunk {
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                executor.chatMessages[assistantMessageIndex].createdAt = chunk.createdAt
                            }
                        }
                        isFirstChunk = false
                    }
                    
                    await flushPendingToFixed(index: assistantMessageIndex, force: false)
                    
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) > throttleInterval || chunk.done {
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(assistantMessageIndex) {
                                executor.chatMessages[assistantMessageIndex].pendingContent = pendingMain
                                executor.chatMessages[assistantMessageIndex].pendingThinking = pendingThinking
                                executor.chatMessages[assistantMessageIndex].latestContent = executor.chatMessages[assistantMessageIndex].fixedContent + executor.chatMessages[assistantMessageIndex].pendingContent
                                
                                if chatSettings.thinkingOption == .on &&
                                    !(executor.chatMessages[assistantMessageIndex].fixedThinking + executor.chatMessages[assistantMessageIndex].pendingThinking).isEmpty &&
                                    !(executor.chatMessages[assistantMessageIndex].fixedContent + executor.chatMessages[assistantMessageIndex].pendingContent).isEmpty &&
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
                        await flushPendingToFixed(index: index, force: true)
                        await MainActor.run {
                            if executor.chatMessages.indices.contains(index) {
                                executor.chatMessages[index].content = executor.chatMessages[index].fixedContent
                                executor.chatMessages[index].thinking = executor.chatMessages[index].fixedThinking.isEmpty ? nil : executor.chatMessages[index].fixedThinking
                                executor.chatMessages[index].pendingContent = ""
                                executor.chatMessages[index].pendingThinking = ""
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
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        executor.chatMessages[index].isStopped = true
                    } else {
                        executor.chatMessages[index].isStopped = false
                        if (executor.chatMessages[index].fixedContent + executor.chatMessages[index].pendingContent).isEmpty {
                            executor.chatMessages[index].fixedContent = ""
                            executor.chatMessages[index].content = ""
                        }
                        generalErrorMessage = "Chat API Error: \(error.localizedDescription)"
                    }
                }
            }
        }
        await MainActor.run { executor.isChatStreaming = false }
    }
}

struct ImageGenerationView: View {
    @EnvironmentObject var executor: CommandExecutor
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @EnvironmentObject var imageSettings: ImageGenerationSettings
    
    @State private var errorMessage: String?
    @State private var generalErrorMessage: String? = nil
    @State private var showingClearConfirm: Bool = false
    
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var imageInputText: String = ""
    
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
            } else if executor.imageMessages.isEmpty {
                ContentUnavailableView {
                    Label("Image Generation", systemImage: "photo.stack.fill")
                } description: {
                    Text("Here you can generate images using models that support image generation.")
                }
            } else {
                ChatMessagesView(
                    messages: $executor.imageMessages,
                    onRetry: retryGeneration,
                    isOverallStreaming: $executor.isImageStreaming,
                    isModelSelected: imageSettings.selectedModelID != nil,
                    isUsingSafeAreaBar: {
                        if #available(iOS 26.0, macOS 26.0, *) { return true }
                        return false
                    }()
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func makeInputArea() -> some View {
        ChatInputView(
            inputText: $imageInputText,
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
                        Text(model.name).tag(model.id as OllamaModel.ID?)
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
                    Text(model.name).tag(model.id as OllamaModel.ID?)
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
                    imageInputText = ""
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
        guard !imageInputText.isEmpty else { return }
        
        let prompt = imageInputText
        imageInputText = ""
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
            let archiveContent = executor.imageMessages[index].latestContent ?? executor.imageMessages[index].content
            let archiveImage = executor.imageMessages[index].latestGeneratedImage ?? executor.imageMessages[index].generatedImage
            let archiveCreatedAt = executor.imageMessages[index].finalCreatedAt ?? executor.imageMessages[index].createdAt
            let archiveTotalDuration = executor.imageMessages[index].finalTotalDuration ?? executor.imageMessages[index].totalDuration
            
            let archived = ChatMessage(
                role: "assistant",
                content: archiveContent,
                createdAt: archiveCreatedAt,
                totalDuration: archiveTotalDuration,
                isStreaming: false,
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
                steps: imageSettings.finalSteps
            ) {
                guard let index = executor.imageMessages.firstIndex(where: { $0.id == messageId }) else { break }
                
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
                    executor.imageMessages[index].isStopped = true
                    // 500エラーなどの場合にメッセージを表示
                    if executor.imageMessages[index].generatedImage == nil {
                        executor.imageMessages[index].fixedContent = "Error: \(error.localizedDescription)"
                    }
                    generalErrorMessage = "Image Generation Error: \(error.localizedDescription)"
                }
            }
        }
        await MainActor.run { 
            executor.isImageStreaming = false 
            executor.updateIsImageStreaming()
        }
    }
}
