import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
    @EnvironmentObject var serverManager: ServerManager
    @Binding var selectedModelID: OllamaModel.ID?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String?
    @Binding var isStreamingEnabled: Bool
    @Binding var showingInspector: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption
    
    private var currentSelectedModel: OllamaModel? {
        if let id = selectedModelID {
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
            if messages.isEmpty {
                ContentUnavailableView {
                    Label("Chat", systemImage: "message.fill")
                } description: {
                    Text("Here you can perform a simple chat to check the model.")
                }
            } else {
                ChatMessagesView(messages: $messages, onRetry: retryMessage)
            }

            VStack {
                Spacer()
                ChatInputView(inputText: $inputText, isStreaming: $isStreaming, selectedModel: currentSelectedModel) {
                    sendMessage()
                } stopMessage: {
                    if let lastAssistantMessageIndex = messages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                        messages[lastAssistantMessageIndex].isStreaming = false
                        messages[lastAssistantMessageIndex].isStopped = true
                    }
                    isStreaming = false
                    executor.cancelChatStreaming()
                }
            }
        }
        .navigationTitle("Chat")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .onAppear {
            print("ChatView appeared. Models: \(executor.models.count)")
        }
        .onChange(of: executor.models) { _, newModels in
            if let currentSelectedModelID = selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
                selectedModelID = newModels.first?.id
            } else if selectedModelID == nil, let firstModel = newModels.first {
                selectedModelID = firstModel.id
            }
        }
        .onChange(of: selectedModelID) { _, _ in
            contextWindowValue = 2048.0
            guard let model = currentSelectedModel else {
                Task { @MainActor in
                    executor.selectedModelContextLength = nil
                    executor.selectedModelCapabilities = nil
                }
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
                    await MainActor.run {
                        executor.selectedModelContextLength = contextLength
                        executor.selectedModelCapabilities = response.capabilities
                    }
                } else {
                    await MainActor.run {
                        executor.selectedModelContextLength = nil
                        executor.selectedModelCapabilities = nil
                    }
                }
            }
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Select Model", selection: $selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                if executor.models.isEmpty {
                    Text("No models available")
                        .tag(OllamaModel.noModelsAvailable.id as OllamaModel.ID?)
                        .selectionDisabled()
                } else {
                    ForEach(executor.models) { model in
                        Text(model.name).tag(model.id as OllamaModel.ID?)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        if #available(macOS 26, *) {
            ToolbarSpacer()
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                messages.removeAll()
                inputText = ""
                isStreaming = false
                errorMessage = nil
            }) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
    }

    private func sendMessage() {
        guard let model = currentSelectedModel else {
            errorMessage = "Please select a model first."
            return
        }
        guard !inputText.isEmpty else { return }

        isStreaming = true
        let userMessageContent = inputText
        inputText = ""

        let userMessage = ChatMessage(role: "user", content: userMessageContent, createdAt: MessageView.iso8601Formatter.string(from: Date()))
        messages.append(userMessage)

        var apiMessages = messages
        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
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
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        Task {
            await streamAssistantResponse(for: assistantMessageId, with: apiMessages, model: model)
        }
    }

    // 過去リビジョン参照中でも、最新の完成版だけをアーカイブしてリトライ開始する
    private func retryMessage(for messageId: UUID, with messageToRetry: ChatMessage) {
        guard let indexToRetry = messages.firstIndex(where: { $0.id == messageId }) else {
            print("Retry failed: Message with ID \(messageId) not found.")
            return
        }
        guard indexToRetry == messages.count - 1 else {
            print("Retry failed: Message is not the last one.")
            return
        }
        guard !messages[indexToRetry].isStreaming else {
            print("Retry failed: Message is still streaming.")
            return
        }
        // 直前のユーザーメッセージまでをAPIに渡す
        guard indexToRetry > 0, messages[indexToRetry - 1].role == "user" else {
            print("Retry failed: User message not found immediately before assistant message at index \(indexToRetry).")
            return
        }
        let userMessageIndex = indexToRetry - 1

        // 1) 最新の完成版を厳密に選ぶ（参照中の状態に依存しない）
        // 本文は latestContent > content > fixed+pending の順
        let latestCandidate = messages[indexToRetry].latestContent ?? ""
        let contentCandidate = messages[indexToRetry].content
        let bufferedCandidate = messages[indexToRetry].fixedContent + messages[indexToRetry].pendingContent
        let archiveContent: String = {
            if !latestCandidate.isEmpty { return latestCandidate }
            if !contentCandidate.isEmpty { return contentCandidate }
            return bufferedCandidate
        }()

        // Thinking は finalThinking > thinking > fixed+pending > nil
        let finalThinkingCandidate = messages[indexToRetry].finalThinking
        let liveThinkingCandidate = messages[indexToRetry].thinking
        let bufferedThinkingCandidate = messages[indexToRetry].fixedThinking + messages[indexToRetry].pendingThinking
        let archiveThinking: String? = {
            if let v = finalThinkingCandidate, !v.isEmpty { return v }
            if let v = liveThinkingCandidate, !v.isEmpty { return v }
            if !bufferedThinkingCandidate.isEmpty { return bufferedThinkingCandidate }
            return nil
        }()

        // 2) 履歴アーカイブ（この関数内のみで1回）
        let archived = ChatMessage(
            role: messages[indexToRetry].role,
            content: archiveContent,
            thinking: archiveThinking,
            images: messages[indexToRetry].images,
            toolCalls: messages[indexToRetry].toolCalls,
            toolName: messages[indexToRetry].toolName,
            createdAt: messages[indexToRetry].createdAt,
            totalDuration: messages[indexToRetry].finalTotalDuration ?? messages[indexToRetry].totalDuration,
            evalCount: messages[indexToRetry].finalEvalCount ?? messages[indexToRetry].evalCount,
            evalDuration: messages[indexToRetry].finalEvalDuration ?? messages[indexToRetry].evalDuration,
            isStreaming: false,
            isStopped: messages[indexToRetry].finalIsStopped || messages[indexToRetry].isStopped,
            isThinkingCompleted: messages[indexToRetry].finalIsThinkingCompleted || messages[indexToRetry].isThinkingCompleted
        )
        archived.revisions = messages[indexToRetry].revisions
        archived.currentRevisionIndex = messages[indexToRetry].currentRevisionIndex
        archived.originalContent = messages[indexToRetry].originalContent
        archived.latestContent = messages[indexToRetry].latestContent
        archived.finalThinking = messages[indexToRetry].finalThinking
        archived.finalIsThinkingCompleted = messages[indexToRetry].finalIsThinkingCompleted
        archived.finalCreatedAt = messages[indexToRetry].finalCreatedAt ?? messages[indexToRetry].createdAt
        archived.finalTotalDuration = messages[indexToRetry].finalTotalDuration ?? messages[indexToRetry].totalDuration
        archived.finalEvalCount = messages[indexToRetry].finalEvalCount ?? messages[indexToRetry].evalCount
        archived.finalEvalDuration = messages[indexToRetry].finalEvalDuration ?? messages[indexToRetry].evalDuration
        archived.finalIsStopped = messages[indexToRetry].finalIsStopped || messages[indexToRetry].isStopped

        messages[indexToRetry].revisions.append(archived)
        // 参照位置は常に最新（末尾の次 = 現在バージョン）
        messages[indexToRetry].currentRevisionIndex = messages[indexToRetry].revisions.count

        // 3) 再実行準備（表示バッファも初期化）
        messages[indexToRetry].content = ""
        messages[indexToRetry].thinking = nil
        messages[indexToRetry].fixedContent = ""
        messages[indexToRetry].pendingContent = ""
        messages[indexToRetry].fixedThinking = ""
        messages[indexToRetry].pendingThinking = ""
        messages[indexToRetry].isStreaming = true
        messages[indexToRetry].isStopped = false
        messages[indexToRetry].isThinkingCompleted = false
        messages[indexToRetry].createdAt = MessageView.iso8601Formatter.string(from: Date())
        messages[indexToRetry].totalDuration = nil
        messages[indexToRetry].evalCount = nil
        messages[indexToRetry].evalDuration = nil

        // 4) APIに出すメッセージ（ユーザー発話まで）
        var apiMessages = Array(messages.prefix(userMessageIndex + 1))
        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
            apiMessages.insert(systemMessage, at: 0)
        }

        guard let model = currentSelectedModel else {
            errorMessage = "Please select a model first."
            return
        }

        isStreaming = true
        Task { await streamAssistantResponse(for: messageId, with: apiMessages, model: model) }
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
            guard messages.indices.contains(index) else { return }
            if force || pendingMain.count >= flushCharThreshold || (flushNewlinePreferred && pendingMain.contains("\n")) {
                let toAppend = pendingMain
                pendingMain.removeAll(keepingCapacity: true)
                let base = messages[index].fixedContent
                let newFixed = base + toAppend
                await MainActor.run {
                    if messages.indices.contains(index) { messages[index].fixedContent = newFixed }
                }
            }
            if force || pendingThinking.count >= flushCharThreshold || (flushNewlinePreferred && pendingThinking.contains("\n")) {
                let toAppend = pendingThinking
                pendingThinking.removeAll(keepingCapacity: true)
                let base = messages[index].fixedThinking
                let newFixed = base + toAppend
                await MainActor.run {
                    if messages.indices.contains(index) { messages[index].fixedThinking = newFixed }
                }
            }
        }

        do {
            for try await chunk in executor.chat(
                model: model.name,
                messages: apiMessages,
                stream: isStreamingEnabled,
                useCustomChatSettings: useCustomChatSettings,
                isTemperatureEnabled: isTemperatureEnabled,
                chatTemperature: chatTemperature,
                isContextWindowEnabled: isContextWindowEnabled,
                contextWindowValue: contextWindowValue,
                isSystemPromptEnabled: isSystemPromptEnabled,
                systemPrompt: systemPrompt,
                thinkingOption: thinkingOption,
                tools: nil
            ) {
                guard let assistantMessageIndex = messages.firstIndex(where: { $0.id == messageId }) else { continue }

                if let messageChunk = chunk.message {
                    if thinkingOption == .on {
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
                                if messages.indices.contains(assistantMessageIndex) {
                                    messages[assistantMessageIndex].isThinkingCompleted = true
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
                            if messages.indices.contains(assistantMessageIndex) {
                                messages[assistantMessageIndex].createdAt = chunk.createdAt
                            }
                        }
                        isFirstChunk = false
                    }

                    await flushPendingToFixed(index: assistantMessageIndex, force: false)

                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) > throttleInterval || chunk.done {
                        await MainActor.run {
                            if messages.indices.contains(assistantMessageIndex) {
                                messages[assistantMessageIndex].pendingContent = pendingMain
                                messages[assistantMessageIndex].pendingThinking = pendingThinking
                                messages[assistantMessageIndex].latestContent = messages[assistantMessageIndex].fixedContent + messages[assistantMessageIndex].pendingContent

                                if thinkingOption == .on &&
                                    !(messages[assistantMessageIndex].fixedThinking + messages[assistantMessageIndex].pendingThinking).isEmpty &&
                                    !(messages[assistantMessageIndex].fixedContent + messages[assistantMessageIndex].pendingContent).isEmpty &&
                                    !messages[assistantMessageIndex].isThinkingCompleted {
                                    messages[assistantMessageIndex].isThinkingCompleted = true
                                }
                            }
                        }
                        lastUIUpdateTime = now
                    }
                }

                if chunk.done {
                    if let index = messages.firstIndex(where: { $0.id == messageId }), messages.indices.contains(index) {
                        await flushPendingToFixed(index: index, force: true)
                        await MainActor.run {
                            if messages.indices.contains(index) {
                                messages[index].content = messages[index].fixedContent
                                messages[index].thinking = messages[index].fixedThinking.isEmpty ? nil : messages[index].fixedThinking
                                messages[index].pendingContent = ""
                                messages[index].pendingThinking = ""
                                messages[index].totalDuration = chunk.totalDuration
                                messages[index].evalCount = chunk.evalCount
                                messages[index].evalDuration = chunk.evalDuration
                                messages[index].isStreaming = false
                                if thinkingOption == .on && messages[index].thinking != nil && !messages[index].isThinkingCompleted {
                                    messages[index].isThinkingCompleted = true
                                }
                                messages[index].finalThinking = messages[index].thinking
                                messages[index].finalIsThinkingCompleted = messages[index].isThinkingCompleted
                                messages[index].finalCreatedAt = messages[index].createdAt
                                messages[index].finalTotalDuration = messages[index].totalDuration
                                messages[index].finalEvalCount = messages[index].evalCount
                                messages[index].finalEvalDuration = messages[index].evalDuration
                                messages[index].finalIsStopped = messages[index].isStopped
                            }
                        }
                    }
                }
            }
        } catch {
            print("Chat streaming error or cancelled: \(error)")
            if let index = messages.firstIndex(where: { $0.id == messageId }), messages.indices.contains(index) {
                await MainActor.run {
                    messages[index].isStreaming = false
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        messages[index].isStopped = true
                    } else {
                        messages[index].isStopped = false
                        errorMessage = "Chat API Error: \(error.localizedDescription)"
                    }
                }
            }
        }
        await MainActor.run { isStreaming = false }
    }
}
