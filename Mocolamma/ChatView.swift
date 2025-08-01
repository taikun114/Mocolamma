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
    @State private var lastUpdateTime: Date = Date() // UI更新バッファリング用
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
    @State private var isInsideThinkingBlock: Bool = false

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
                ChatMessagesView(messages: $messages, onRetry: retryMessage) // onRetryを渡す
            }

            VStack {
                
                Spacer()
                ChatInputView(inputText: $inputText, isStreaming: $isStreaming, selectedModel: currentSelectedModel) {
                    sendMessage()
                } stopMessage: {
                    // ストリーミング中のアシスタントメッセージを見つけて、その状態を即座に更新
                    if let lastAssistantMessageIndex = messages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                        messages[lastAssistantMessageIndex].isStreaming = false
                        messages[lastAssistantMessageIndex].isStopped = true
                    }
                    isStreaming = false // ChatView全体のストリーミング状態をfalseに設定
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
            // 初期モデルの選択は行わない (「Select Model」をデフォルトにするため)
        }
        .onChange(of: executor.models) { _, newModels in
            print("Models changed. New models count: \(newModels.count)")
            // モデルリストが更新された場合、現在選択されているモデルがまだ存在するか確認
            if let currentSelectedModelID = selectedModelID, !newModels.contains(where: { $0.id == currentSelectedModelID }) {
                selectedModelID = newModels.first?.id // 存在しない場合は最初のモデルを選択
            } else if selectedModelID == nil, let firstModel = newModels.first {
                selectedModelID = firstModel.id // まだ何も選択されていない場合は最初のモデルを選択
            }
        }
        // 変更点: selectedModel の変更を監視してコンテキスト長を更新する
        .onChange(of: selectedModelID) { _, newModelID in
            // モデルが変更されたら、コンテキストウィンドウの値をリセット
            contextWindowValue = 2048.0
            
            guard let model = currentSelectedModel else {
                Task { @MainActor in
                    executor.selectedModelContextLength = nil
                    executor.selectedModelCapabilities = nil // capabilitiesもリセット
                }
                return
            }
            Task {
                if let response = await executor.fetchModelInfo(modelName: model.name) {
                    // コンテキスト長を抽出
                    let contextLength: Int?
                    if let modelInfo = response.model_info,
                       // .context_length で終わるキーを検索
                       let contextLengthValue = modelInfo.first(where: { $0.key.hasSuffix(".context_length") })?.value,
                       case .int(let length) = contextLengthValue {
                        contextLength = length
                    } else {
                        contextLength = nil
                    }
                    
                    // MainActorでプロパティを更新
                    await MainActor.run {
                        executor.selectedModelContextLength = contextLength
                        executor.selectedModelCapabilities = response.capabilities // capabilitiesを更新
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
            .frame(width: 150) // Adjust width as needed
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

    private var menuLabel: some View {
        HStack {
            Image(systemName: "tray.full")
            if let modelName = currentSelectedModel?.name {
                Text(modelName.prefix(15).appending(modelName.count > 15 ? "..." : ""))
            } else {
                Text("Select Model")
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
        inputText = "" // Clear input field immediately

        // Add user message to chat history
        let userMessage = ChatMessage(role: "user", content: userMessageContent, createdAt: MessageView.iso8601Formatter.string(from: Date()))
        messages.append(userMessage)

        // Prepare messages for API request (including history)
        var apiMessages = messages.map {
            ChatMessage(role: $0.role, content: $0.content, images: $0.images, toolCalls: $0.toolCalls, toolName: $0.toolName)
        }

        // Add system prompt if enabled
        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
            apiMessages.insert(systemMessage, at: 0)
        }

        // Add a placeholder for the assistant's response
        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        Task {
            let lastAssistantMessageIndex: Int? = messages.firstIndex(where: { $0.id == assistantMessageId })
            var lastUIUpdateTime = Date()
            let updateInterval = 0.1 // 100ms
            let updateCharacterCount = 20 // 20文字ごと
            var isFirstChunk = true
            isInsideThinkingBlock = false // Reset for new message
            var accumulatedThinkingContent = ""
            var accumulatedMainContent = ""

            do {
                for try await chunk in executor.chat(model: model.name, messages: apiMessages, stream: isStreamingEnabled, useCustomChatSettings: useCustomChatSettings, isTemperatureEnabled: isTemperatureEnabled, chatTemperature: chatTemperature, isContextWindowEnabled: isContextWindowEnabled, contextWindowValue: contextWindowValue, isSystemPromptEnabled: isSystemPromptEnabled, systemPrompt: systemPrompt, thinkingOption: thinkingOption, tools: nil) {
                    if let messageChunk = chunk.message {
                        // Prioritize messageChunk.thinking if thinkingOption is .on
                        if thinkingOption == .on {
                            if let apiThinking = messageChunk.thinking {
                                accumulatedThinkingContent += apiThinking
                            }
                            // If thinkingOption is .on, assume main content is just messageChunk.content
                            accumulatedMainContent += messageChunk.content
                        } else {
                            // If thinkingOption is .none or .off, parse <think> tags from messageChunk.content
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
                                if let index = lastAssistantMessageIndex {
                                    messages[index].isThinkingCompleted = true
                                }
                            } else if isInsideThinkingBlock {
                                accumulatedThinkingContent += currentContentChunk
                            } else {
                                accumulatedMainContent += currentContentChunk
                            }
                        }

                        // Update message object
                        if let index = lastAssistantMessageIndex {
                            messages[index].thinking = accumulatedThinkingContent
                            messages[index].content = accumulatedMainContent

                            // 思考完了のロジックを更新
                            if !messages[index].isThinkingCompleted { // まだ思考完了になっていない場合のみチェック
                                if thinkingOption == .on {
                                    // thinkingOptionが.onの場合、thinkingコンテンツがあり、かつメインコンテンツが流れ始めたら思考完了
                                    if !accumulatedThinkingContent.isEmpty && !accumulatedMainContent.isEmpty {
                                        messages[index].isThinkingCompleted = true
                                    }
                                }
                            }
                        }

                        if isFirstChunk {
                            if let index = lastAssistantMessageIndex {
                                messages[index].createdAt = chunk.createdAt
                                lastUIUpdateTime = Date()
                            }
                            isFirstChunk = false
                        }

                        let now = Date()
                        let timeSinceLastUpdate = now.timeIntervalSince(lastUIUpdateTime)

                        // Update UI based on buffer size or time interval
                        if let index = lastAssistantMessageIndex, (accumulatedMainContent.count > messages[index].content.count + updateCharacterCount || timeSinceLastUpdate > updateInterval || chunk.done) {
                            lastUIUpdateTime = now
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics and set isStreaming to false
                        if messages.indices.contains(index) {
                            messages[index].totalDuration = chunk.totalDuration
                            messages[index].evalCount = chunk.evalCount
                            messages[index].evalDuration = chunk.evalDuration
                            messages[index].isStreaming = false
                            // If thinkingOption is .on and thinking content exists, mark as completed if not already by </think>
                            if thinkingOption == .on && messages[index].thinking != nil && !messages[index].isThinkingCompleted {
                                messages[index].isThinkingCompleted = true
                            }
                        }
                    }
                }
            } catch {
                print("Chat streaming error or cancelled: \(error)")
                if let index = lastAssistantMessageIndex, messages.indices.contains(index) {
                    var updatedMessage = messages[index]
                    updatedMessage.isStreaming = false // Streaming stopped due to error or cancellation
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        updatedMessage.isStopped = true // Explicitly stopped by user
                    } else {
                        updatedMessage.isStopped = false // Stopped due to other error
                        errorMessage = "Chat API Error: \(error.localizedDescription)" // Only show error for non-cancellation errors
                    }
                    messages[index] = updatedMessage // Update the message in the array
                }
            }
            isStreaming = false // Reset ChatView's overall streaming state
        }
    }

    private func retryMessage(for messageId: UUID) {
        guard let indexToRetry = messages.firstIndex(where: { $0.id == messageId }) else {
            print("Retry failed: Message with ID \(messageId) not found.")
            return
        }

        // 再試行するアシスタントメッセージが最後のメッセージであることを確認
        guard indexToRetry == messages.count - 1 else {
            print("Retry failed: Message is not the last one.")
            return
        }

        // 再試行するアシスタントメッセージが停止済みであることを確認
        guard messages[indexToRetry].isStopped else {
            print("Retry failed: Message is not stopped.")
            return
        }

        // ユーザーメッセージのインデックスを見つける
        // 停止されたアシスタントメッセージの直前のメッセージがユーザーメッセージであることを期待
        let userMessageIndex: Int
        if indexToRetry > 0 && messages[indexToRetry - 1].role == "user" {
            userMessageIndex = indexToRetry - 1
        } else {
            print("Retry failed: User message not found immediately before assistant message at index \(indexToRetry).")
            return
        }

        // 再試行するアシスタントメッセージとその後のメッセージを削除
        messages.removeSubrange(indexToRetry..<messages.count)

        // Prepare messages for API request (including history) up to the user message
        var apiMessages = messages.prefix(userMessageIndex + 1).map { msg in
            ChatMessage(role: msg.role, content: msg.content, images: msg.images, toolCalls: msg.toolCalls, toolName: msg.toolName)
        }

        // Add system prompt if enabled
        if isSystemPromptEnabled && !systemPrompt.isEmpty {
            let systemMessage = ChatMessage(role: "system", content: systemPrompt)
            apiMessages.insert(systemMessage, at: 0)
        }

        print("Retrying with API messages: \(apiMessages.map { $0.content })") // デバッグ用ログを追加

        guard let model = currentSelectedModel else {
            errorMessage = "Please select a model first."
            return
        }

        

        // Add a placeholder for the assistant's response
        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        isStreaming = true // 全体のストリーミング状態をtrueに設定

        Task {
            let lastAssistantMessageIndex: Int? = messages.firstIndex(where: { $0.id == assistantMessageId })
            var lastUIUpdateTime = Date()
            let updateInterval = 0.1 // 100ms
            let updateCharacterCount = 20 // 20文字ごと
            var isFirstChunk = true
            isInsideThinkingBlock = false // Reset for new message
            var accumulatedThinkingContent = ""
            var accumulatedMainContent = ""

            do {
                for try await chunk in executor.chat(model: model.name, messages: apiMessages, stream: isStreamingEnabled, useCustomChatSettings: useCustomChatSettings, isTemperatureEnabled: isTemperatureEnabled, chatTemperature: chatTemperature, isContextWindowEnabled: isContextWindowEnabled, contextWindowValue: contextWindowValue, isSystemPromptEnabled: isSystemPromptEnabled, systemPrompt: systemPrompt, thinkingOption: thinkingOption, tools: nil) {
                    if let messageChunk = chunk.message {
                        // Prioritize messageChunk.thinking if thinkingOption is .on
                        if thinkingOption == .on {
                            if let apiThinking = messageChunk.thinking {
                                accumulatedThinkingContent += apiThinking
                            }
                            // If thinkingOption is .on, assume main content is just messageChunk.content
                            accumulatedMainContent += messageChunk.content
                        } else {
                            // If thinkingOption is .none or .off, parse <think> tags from messageChunk.content
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
                                if let index = lastAssistantMessageIndex {
                                    messages[index].isThinkingCompleted = true
                                }
                            } else if isInsideThinkingBlock {
                                accumulatedThinkingContent += currentContentChunk
                            } else {
                                accumulatedMainContent += currentContentChunk
                            }
                        }

                        // Update message object
                        if let index = lastAssistantMessageIndex {
                            messages[index].thinking = accumulatedThinkingContent
                            messages[index].content = accumulatedMainContent

                            // 思考完了のロジックを更新
                            if !messages[index].isThinkingCompleted { // まだ思考完了になっていない場合のみチェック
                                if thinkingOption == .on {
                                    // thinkingOptionが.onの場合、thinkingコンテンツがあり、かつメインコンテンツが流れ始めたら思考完了
                                    if !accumulatedThinkingContent.isEmpty && !accumulatedMainContent.isEmpty {
                                        messages[index].isThinkingCompleted = true
                                    }
                                }
                            }
                        }

                        if isFirstChunk {
                            if let index = lastAssistantMessageIndex {
                                messages[index].createdAt = chunk.createdAt
                                lastUIUpdateTime = Date()
                            }
                            isFirstChunk = false
                        }

                        let now = Date()
                        let timeSinceLastUpdate = now.timeIntervalSince(lastUIUpdateTime)

                        // Update UI based on buffer size or time interval
                        if let index = lastAssistantMessageIndex, (accumulatedMainContent.count > messages[index].content.count + updateCharacterCount || timeSinceLastUpdate > updateInterval || chunk.done) {
                            lastUIUpdateTime = now
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics and set isStreaming to false
                        if messages.indices.contains(index) {
                            messages[index].totalDuration = chunk.totalDuration
                            messages[index].evalCount = chunk.evalCount
                            messages[index].evalDuration = chunk.evalDuration
                            messages[index].isStreaming = false
                            // If thinkingOption is .on and thinking content exists, mark as completed if not already by </think>
                            if thinkingOption == .on && messages[index].thinking != nil && !messages[index].isThinkingCompleted {
                                messages[index].isThinkingCompleted = true
                            }
                        }
                    }
                }
            } catch {
                print("Chat streaming error or cancelled: \(error)")
                if let index = lastAssistantMessageIndex, messages.indices.contains(index) {
                    var updatedMessage = messages[index]
                    updatedMessage.isStreaming = false // Streaming stopped due to error or cancellation
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        updatedMessage.isStopped = true // Explicitly stopped by user
                    } else {
                        updatedMessage.isStopped = false // Stopped due to other error
                        errorMessage = "Chat API Error: \(error.localizedDescription)" // Only show error for non-cancellation errors
                    }
                    messages[index] = updatedMessage // Update the message in the array
                }
            }
            isStreaming = false // Reset ChatView's overall streaming state
        }
    }
}

// MARK: - MessageView

struct MessageView: View {
    let message: ChatMessage
    let isLastAssistantMessage: Bool // 新しいプロパティ
    let onRetry: ((UUID) -> Void)? // 新しいクロージャ
    @State private var isHovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    // For parsing ISO8601 date strings from API
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
                .lineSpacing(4) // 行間を調整
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
                        if message.role == "assistant", !message.isStopped, let evalDuration = message.evalDuration { // isStoppedでない場合にのみ加算
                            // eval_durationはナノ秒なので、秒に変換して加算
                            return createdAtDate.addingTimeInterval(Double(evalDuration) / 1_000_000_000.0)
                        } else {
                            return createdAtDate
                        }
                    }
                    return Date() // Fallback to current date if createdAt is nil or invalid
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
                // 「Retry」ボタンの追加
                if message.role == "assistant" && message.isStopped && isLastAssistantMessage {
                    Button("Retry") {
                        onRetry?(message.id)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
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
        .onHover { hovering in
            isHovering = hovering
            print("MessageView: isHovering=\(isHovering), isStreaming=\(message.isStreaming), isStopped=\(message.isStopped)")
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
