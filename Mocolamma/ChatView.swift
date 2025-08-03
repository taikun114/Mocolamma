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
        .toolbar {
            toolbarContent
        }
        .onAppear {
            print("ChatView appeared. Models: \(executor.models.count)")
        }
        .onChange(of: executor.models) { _, newModels in
            print("Models changed. New models count: \(newModels.count)")
            if let currentSelectedModelID = selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
                selectedModelID = newModels.first?.id
            } else if selectedModelID == nil, let firstModel = newModels.first {
                selectedModelID = firstModel.id
            }
        }
        .onChange(of: selectedModelID) { _, newModelID in
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
                        print("ChatView: Updated context length to \(contextLength ?? -1) for model \(model.name)")
                        print("ChatView: Updated capabilities to \(response.capabilities ?? []) for model \(model.name)")
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
                        Text(model.name)
                            .tag(model.id as OllamaModel.ID?)
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

        var apiMessages = messages // ChatMessageがクラスになったため、直接渡す
        
        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
            apiMessages.insert(systemMessage, at: 0)
        }

        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        placeholderMessage.revisions = []
        placeholderMessage.currentRevisionIndex = 0
        placeholderMessage.originalContent = ""
        placeholderMessage.latestContent = ""
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        Task {
            await streamAssistantResponse(for: assistantMessageId, with: apiMessages, model: model)
        }
    }

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
        
        let userMessageIndex: Int
        if indexToRetry > 0 && messages[indexToRetry - 1].role == "user" {
            userMessageIndex = indexToRetry - 1
        } else {
            print("Retry failed: User message not found immediately before assistant message at index \(indexToRetry).")
            return
        }

        let messageToArchive = ChatMessage(role: messages[indexToRetry].role, content: messages[indexToRetry].content, thinking: messages[indexToRetry].thinking, images: messages[indexToRetry].images, toolCalls: messages[indexToRetry].toolCalls, toolName: messages[indexToRetry].toolName, createdAt: messages[indexToRetry].createdAt, totalDuration: messages[indexToRetry].totalDuration, evalCount: messages[indexToRetry].evalCount, evalDuration: messages[indexToRetry].evalDuration, isStreaming: messages[indexToRetry].isStreaming, isStopped: messages[indexToRetry].isStopped, isThinkingCompleted: messages[indexToRetry].isThinkingCompleted)
        messageToArchive.revisions = messages[indexToRetry].revisions
        messageToArchive.currentRevisionIndex = messages[indexToRetry].currentRevisionIndex
        messageToArchive.originalContent = messages[indexToRetry].originalContent
        messageToArchive.latestContent = messages[indexToRetry].latestContent
        messageToArchive.finalThinking = messages[indexToRetry].finalThinking
        messageToArchive.finalIsThinkingCompleted = messages[indexToRetry].finalIsThinkingCompleted
        messageToArchive.finalCreatedAt = messages[indexToRetry].finalCreatedAt
        messageToArchive.finalTotalDuration = messages[indexToRetry].finalTotalDuration
        messageToArchive.finalEvalCount = messages[indexToRetry].finalEvalCount
        messageToArchive.finalEvalDuration = messages[indexToRetry].finalEvalDuration
        messageToArchive.finalIsStopped = messages[indexToRetry].finalIsStopped

        messages[indexToRetry].revisions.append(messageToArchive)
        messages[indexToRetry].currentRevisionIndex = messages[indexToRetry].revisions.count

        messages[indexToRetry].content = ""
        messages[indexToRetry].thinking = nil
        messages[indexToRetry].isStreaming = true
        messages[indexToRetry].isStopped = false
        messages[indexToRetry].isThinkingCompleted = false
        messages[indexToRetry].createdAt = MessageView.iso8601Formatter.string(from: Date())
        messages[indexToRetry].totalDuration = nil
        messages[indexToRetry].evalCount = nil
        messages[indexToRetry].evalDuration = nil

        var apiMessages = Array(messages.prefix(userMessageIndex + 1)) // ChatMessageがクラスになったため、直接渡す

        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
            apiMessages.insert(systemMessage, at: 0)
        }

        print("Retrying with API messages: \(apiMessages.map { $0.content })")

        guard let model = currentSelectedModel else {
            errorMessage = "Please select a model first."
            return
        }

        isStreaming = true
        
        Task {
            await streamAssistantResponse(for: messageId, with: apiMessages, model: model)
        }
    }
    
    /// ストリーミング応答を処理し、UIをバッファリングしながら更新する共通メソッド
    private func streamAssistantResponse(for messageId: UUID, with apiMessages: [ChatMessage], model: OllamaModel) async {
        var lastUIUpdateTime = Date()
        let updateInterval = 0.1 // 100ms
        var isFirstChunk = true
        var isInsideThinkingBlock = false
        var accumulatedThinkingContent = ""
        var accumulatedMainContent = ""

        do {
            for try await chunk in executor.chat(model: model.name, messages: apiMessages, stream: isStreamingEnabled, useCustomChatSettings: useCustomChatSettings, isTemperatureEnabled: isTemperatureEnabled, chatTemperature: chatTemperature, isContextWindowEnabled: isContextWindowEnabled, contextWindowValue: contextWindowValue, isSystemPromptEnabled: isSystemPromptEnabled, systemPrompt: systemPrompt, thinkingOption: thinkingOption, tools: nil) {
                
                guard let assistantMessageIndex = messages.firstIndex(where: { $0.id == messageId }) else { continue }
                
                if let messageChunk = chunk.message {
                    if thinkingOption == .on {
                        if let apiThinking = messageChunk.thinking {
                            accumulatedThinkingContent += apiThinking
                        }
                        accumulatedMainContent += messageChunk.content
                    } else {
                        var currentContentChunk = messageChunk.content
                        if let thinkStartIndex = currentContentChunk.range(of: "<think>") {
                            isInsideThinkingBlock = true
                            accumulatedMainContent += String(currentContentChunk[..<thinkStartIndex.lowerBound])
                            currentContentChunk = String(currentContentChunk[thinkStartIndex.upperBound...])
                        }
                        if let thinkEndIndex = currentContentChunk.range(of: "</think>") {
                            isInsideThinkingBlock = false
                            accumulatedThinkingContent += String(currentContentChunk[..<thinkEndIndex.lowerBound])
                            accumulatedMainContent += String(currentContentChunk[thinkEndIndex.upperBound...])
                            if messages.indices.contains(assistantMessageIndex) {
                                messages[assistantMessageIndex].isThinkingCompleted = true
                            }
                        } else if isInsideThinkingBlock {
                            accumulatedThinkingContent += currentContentChunk
                        } else {
                            accumulatedMainContent += currentContentChunk
                        }
                    }

                    if isFirstChunk {
                        if messages.indices.contains(assistantMessageIndex) {
                            messages[assistantMessageIndex].createdAt = chunk.createdAt
                        }
                        isFirstChunk = false
                    }

                    let now = Date()
                    let timeSinceLastUpdate = now.timeIntervalSince(lastUIUpdateTime)

                    // バッファリング条件に基づいてUIを更新 (時間ベースのみ)
                    if timeSinceLastUpdate > updateInterval || chunk.done {
                        if messages.indices.contains(assistantMessageIndex) {
                            messages[assistantMessageIndex].thinking = accumulatedThinkingContent
                            messages[assistantMessageIndex].content = accumulatedMainContent
                            messages[assistantMessageIndex].latestContent = accumulatedMainContent

                            if !messages[assistantMessageIndex].isThinkingCompleted {
                                if thinkingOption == .on && !accumulatedThinkingContent.isEmpty && !accumulatedMainContent.isEmpty {
                                    messages[assistantMessageIndex].isThinkingCompleted = true
                                }
                            }
                        }
                        lastUIUpdateTime = now
                    }
                }

                if chunk.done {
                    if let index = messages.firstIndex(where: { $0.id == messageId }), messages.indices.contains(index) {
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
        } catch {
            print("Chat streaming error or cancelled: \(error)")
            if let index = messages.firstIndex(where: { $0.id == messageId }), messages.indices.contains(index) {
                messages[index].isStreaming = false
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    messages[index].isStopped = true
                } else {
                    messages[index].isStopped = false
                    errorMessage = "Chat API Error: \(error.localizedDescription)"
                }
            }
        }
        isStreaming = false
    }
}


