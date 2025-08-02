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

// MARK: - MessageView

struct MessageView: View {
    @ObservedObject var message: ChatMessage // @ObservedObject に変更
    let isLastAssistantMessage: Bool
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @State private var isHovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        return formatter
    }()

    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading) {
            messageContentView
                .padding(10)
                .background(message.role == "user" ? Color.blue : Color.gray.opacity(0.1))
                .cornerRadius(16)
                .lineSpacing(4)
                .markdownTextStyle(\.text) {
                    ForegroundColor(message.role == "user" ? .white : nil)
                }
                .markdownTextStyle(\.code) {
                    FontFamilyVariant(.monospaced)
                    BackgroundColor(message.role == "user" ? .white.opacity(0.2) : .gray.opacity(0.2))
                }
                .markdownBlockStyle(\.paragraph) { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.3))
                        .markdownMargin(top: .zero, bottom: .em(0.8))
                }
                .markdownBlockStyle(\.listItem) { configuration in
                    configuration.label
                        .markdownMargin(top: .em(0.3))
                }
                .markdownBlockStyle(\.blockquote) { configuration in
                    configuration.label
                        .padding()
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(message.role == "user" ? .white : .gray)
                                .frame(width: 4)
                    }
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    ScrollView(.horizontal) {
                        configuration.label
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                            }
                            .markdownMargin(top: .em(0.3))
                            .padding()
                    }
                    .background(message.role == "user" ? .white.opacity(0.2) : .gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.vertical, 8)
                }
                .textSelection(.enabled)
            
            HStack {
                if message.role == "user" {
                    Spacer()
                }
                Text(dateFormatter.string(from: {
                    if let createdAtString = message.createdAt,
                       let createdAtDate = MessageView.iso8601Formatter.date(from: createdAtString) {
                        if message.role == "assistant", !message.isStopped, let evalDuration = message.evalDuration {
                            return createdAtDate.addingTimeInterval(Double(evalDuration) / 1_000_000_000.0)
                        } else {
                            return createdAtDate
                        }
                    }
                    return Date()
                }()))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if message.role == "assistant" {
                    if message.isStopped {
                        Text("Stopped")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if let evalCount = message.evalCount, let evalDuration = message.evalDuration, evalDuration > 0 {
                        Text("\(evalCount) Tokens")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        let tokensPerSecond = Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
                        Text(String(format: "%.2f Tok/s", tokensPerSecond))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if message.role == "assistant" && isLastAssistantMessage && !message.revisions.isEmpty {
                    Button(action: {
                        message.currentRevisionIndex -= 1
                        let revision = message.revisions[message.currentRevisionIndex]
                        message.content = revision.content
                        message.thinking = revision.thinking
                        message.isThinkingCompleted = revision.isThinkingCompleted
                        message.createdAt = revision.createdAt
                        message.totalDuration = revision.totalDuration
                        message.evalCount = revision.evalCount
                        message.evalDuration = revision.evalDuration
                        message.isStopped = revision.isStopped
                    }) {
                        Image(systemName: "chevron.backward")
                            .contentShape(Rectangle())
                            .padding(5)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .help("Previous Revision")
                    .disabled(message.currentRevisionIndex == 0)

                    if message.revisions.count > 0 {
                        Text("\(message.currentRevisionIndex + 1)/\(message.revisions.count + 1)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        message.currentRevisionIndex += 1
                        if message.currentRevisionIndex < message.revisions.count {
                            let revision = message.revisions[message.currentRevisionIndex]
                            message.content = revision.content
                            message.thinking = revision.thinking
                            message.isThinkingCompleted = revision.isThinkingCompleted
                            message.createdAt = revision.createdAt
                            message.totalDuration = revision.totalDuration
                            message.evalCount = revision.evalCount
                            message.evalDuration = revision.evalDuration
                            message.isStopped = revision.isStopped
                        } else {
                            message.content = message.latestContent ?? ""
                            message.thinking = message.finalThinking
                            message.isThinkingCompleted = message.finalIsThinkingCompleted
                            message.createdAt = message.finalCreatedAt
                            message.totalDuration = message.finalTotalDuration
                            message.evalCount = message.finalEvalCount
                            message.evalDuration = message.finalEvalDuration
                            message.isStopped = message.finalIsStopped
                        }
                    }) {
                        Image(systemName: "chevron.forward")
                            .contentShape(Rectangle())
                            .padding(5)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .help("Next Revision")
                    .disabled(message.currentRevisionIndex == message.revisions.count)
                }

                if message.role == "assistant" && isLastAssistantMessage && (!message.isStreaming || message.isStopped) {
                    Button(action: {
                        let messageToRetry = ChatMessage(role: message.role, content: message.content, thinking: message.thinking, images: message.images, toolCalls: message.toolCalls, toolName: message.toolName, createdAt: message.createdAt, totalDuration: message.totalDuration, evalCount: message.evalCount, evalDuration: message.evalDuration, isStreaming: message.isStreaming, isStopped: message.isStopped, isThinkingCompleted: message.isThinkingCompleted)
                        messageToRetry.revisions = message.revisions
                        messageToRetry.currentRevisionIndex = message.currentRevisionIndex
                        messageToRetry.originalContent = message.originalContent
                        messageToRetry.latestContent = message.latestContent
                        messageToRetry.finalThinking = message.finalThinking
                        messageToRetry.finalIsThinkingCompleted = message.finalIsThinkingCompleted
                        messageToRetry.finalCreatedAt = message.finalCreatedAt
                        messageToRetry.finalTotalDuration = message.finalTotalDuration
                        messageToRetry.finalEvalCount = message.finalEvalCount
                        messageToRetry.finalEvalDuration = message.finalEvalDuration
                        messageToRetry.finalIsStopped = message.finalIsStopped

                        message.revisions.append(messageToRetry)
                        message.currentRevisionIndex = message.revisions.count
                        onRetry?(message.id, message) // messageToRetryではなく、元のmessageを渡す
                    }) {
                        Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                            .contentShape(Rectangle())
                            .padding(5)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .help("Retry")
                }

                if message.role == "assistant" && (!message.isStreaming || message.isStopped) {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        var contentToCopy = message.content
                        if let thinking = message.thinking, !thinking.isEmpty {
                            contentToCopy = "<think>\(thinking)</think>\n\(message.content)"
                        }
                        pasteboard.setString(contentToCopy, forType: .string)
                    }) {
                        Image(systemName: "document.on.document")
                            .contentShape(Rectangle())
                            .padding(5)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .help("Copy")
                }

                if message.role == "assistant" {
                    Spacer()
                }
            }
            .opacity(isHovering && (!message.isStreaming || message.isStopped) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var messageContentView: some View {
        if let thinking = message.thinking, !thinking.isEmpty {
            VStack(alignment: .leading) {
                DisclosureGroup {
                    Text(thinking)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(message.isThinkingCompleted ? "Thinking completed" : "Thinking...", systemImage: "brain.filled.head.profile")
                        .foregroundColor(.secondary)
                        .symbolEffect(.pulse, isActive: message.isStreaming && !message.isThinkingCompleted)
                }
                .padding(.bottom, 4)

                if message.isStreaming && message.content.isEmpty && message.thinking == nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(2)
                } else if message.isStopped && message.content.isEmpty {
                    Text("*No message*")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Markdown(message.content)
                }
            }
        } else {
            if message.isStreaming && message.content.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(2)
                // SF Symbolの`doc.on.doc`は非推奨であり、代わりに`document.on.document`を使用すること。
            } else if message.isStopped && message.content.isEmpty {
                Text("*No message*")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Markdown(message.content)
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}
