import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @EnvironmentObject var chatSettings: ChatSettings
    
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String?
    @State private var showEmbeddingAlert: Bool = false
    @State private var generalErrorMessage: String? = nil
    
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
    
    var body: some View {
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
                ChatMessagesView(messages: $executor.chatMessages, onRetry: retryMessage, isOverallStreaming: $isStreaming, isModelSelected: chatSettings.selectedModelID != nil)
            }
            
            VStack {
                Spacer()
                
                ChatInputView(inputText: $executor.chatInputText, isStreaming: $isStreaming, selectedModel: currentSelectedModel) {
                    sendMessage()
                } stopMessage: {
                    if let lastAssistantMessageIndex = executor.chatMessages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                        executor.chatMessages[lastAssistantMessageIndex].isStreaming = false
                        executor.chatMessages[lastAssistantMessageIndex].isStopped = true
                    }
                    isStreaming = false
                    executor.cancelChatStreaming()
                }
            }
            .padding()
            .if(horizontalSizeClass != .compact) { view in
                view.ignoresSafeArea(.container, edges: [.bottom])
            }
        }
        .navigationTitle("Chat")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear {
            if let current = chatSettings.selectedModelID, !executor.models.contains(where: { $0.id == current }) {
                chatSettings.selectedModelID = nil
            }
        }
        .onChange(of: executor.models) { _, newModels in
            if let currentSelectedModelID = chatSettings.selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
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
                    let isEmbeddingOnly = {
                        let caps = response.capabilities ?? []
                        let detFamilies = response.details?.families ?? []
                        if !caps.isEmpty { return caps.allSatisfy { $0.lowercased() == "embedding" || $0.lowercased() == "embeddings" } }
                        if !detFamilies.isEmpty { return detFamilies.count == 1 && detFamilies.first?.lowercased() == "embedding" }
                        return false
                    }()
                    if isEmbeddingOnly {
                        chatSettings.selectedModelID = nil
                        showEmbeddingAlert = true
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
        .alert("This model cannot be used", isPresented: $showEmbeddingAlert) {
            Button("OK") { showEmbeddingAlert = false }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(localized: "This model does not support chat.", comment: "Embedding-only model selection warning body."))
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
        ToolbarItemGroup(placement: .primaryAction) { // Group for Refresh and Model Selection (iOS)
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
            
            Menu {
                Button("Select Model") { chatSettings.selectedModelID = nil }
                if executor.models.isEmpty {
                    Divider()
                    Button(LocalizedStringKey("No models available")) {}
                        .disabled(true)
                }
                ForEach(executor.models) { model in
                    Button(action: { chatSettings.selectedModelID = model.id }) {
                        if chatSettings.selectedModelID == model.id { Image(systemName: "checkmark") }
                        Text(model.name)
                    }
                }
            } label: {
                Image(systemName: chatSettings.selectedModelID != nil ? "tray.full.fill" : "tray.full")
            }
        }
        #else // macOS
        ToolbarItem(placement: .primaryAction) { // Refresh Button (macOS)
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning)
        }
        ToolbarItem(placement: .primaryAction) { // Model Picker (macOS)
            Picker("Select Model", selection: $chatSettings.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                ForEach(executor.models) { model in
                    Text(model.name).tag(model.id as OllamaModel.ID?)
                }
                if executor.models.isEmpty {
                    Divider()
                    Text(LocalizedStringKey("No models available"))
                        .tag(UUID() as OllamaModel.ID?) // Assign a unique, non-nil UUID
                        .selectionDisabled(true)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
        }
        #endif
        
        #if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // Spacer between Model Group and New Chat
        }
        #endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                executor.clearChat()
                isStreaming = false
                errorMessage = nil
            }) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        
        #if os(iOS)
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction) // Spacer between New Chat and Inspector
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: "sidebar.trailing")
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
        
        isStreaming = true
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
            executor.chatMessages.removeAll(where: { (message: ChatMessage) -> Bool in // ChatMessageを明示的に指定
                guard let messageCreatedAt = message.createdAt,
                      let userMessageCreatedAt = userMessage.createdAt else { return false }
                return messageCreatedAt > userMessageCreatedAt && message.role == "assistant" // $0.role を message.role に変更
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
            
            isStreaming = true
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
            
            isStreaming = true
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
        await MainActor.run { isStreaming = false }
    }
}