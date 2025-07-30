import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
    @EnvironmentObject var serverManager: ServerManager
    @State private var selectedModel: OllamaModel?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String?
    @State private var lastUpdateTime: Date = Date() // UI更新バッファリング用

    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }

    var body: some View {
        ZStack {
            ChatMessagesView(messages: $messages, onRetry: retryMessage) // onRetryを渡す

            VStack {
                
                Spacer()
                ChatInputView(inputText: $inputText, isStreaming: $isStreaming, selectedModel: selectedModel) {
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
            // 初期モデルの選択 (もしあれば)
            if selectedModel == nil, let firstModel = executor.models.first {
                selectedModel = firstModel
            }
        }
        .onChange(of: executor.models) { _, newModels in
            print("Models changed. New models count: \(newModels.count)")
            // モデルリストが更新された場合、現在選択されているモデルがまだ存在するか確認
            if let currentSelectedModel = selectedModel, !newModels.contains(where: { $0.id == currentSelectedModel.id }) {
                selectedModel = newModels.first // 存在しない場合は最初のモデルを選択
            } else if selectedModel == nil, let firstModel = newModels.first {
                selectedModel = firstModel // まだ何も選択されていない場合は最初のモデルを選択
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
            Menu {
                if executor.models.isEmpty {
                    Text("No models available")
                        .disabled(true)
                } else {
                    ForEach(executor.models) { model in
                        Button(action: {
                            selectedModel = model
                        }) {
                            HStack {
                                Text(model.name)
                                if selectedModel?.id == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                menuLabel
            }
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
            if let modelName = selectedModel?.name {
                Text(modelName.prefix(15).appending(modelName.count > 15 ? "..." : ""))
            } else {
                Text("Select Model")
            }
        }
    }

    private func sendMessage() {
        guard let model = selectedModel else {
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
        let apiMessages = messages.map { msg in
            ChatMessage(role: msg.role, content: msg.content, images: msg.images, toolCalls: msg.toolCalls, toolName: msg.toolName)
        }

        let chatRequest = ChatRequest(model: model.name, messages: apiMessages, stream: true, options: nil, tools: nil)

        // Add a placeholder for the assistant's response
        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        Task {
            let lastAssistantMessageIndex: Int? = messages.firstIndex(where: { $0.id == assistantMessageId })
            var accumulatedContent = ""
            var lastUIUpdateTime = Date()
            let updateInterval = 0.1 // 100ms
            let updateCharacterCount = 20 // 20文字ごと
            var isFirstChunk = true

            do {
                for try await chunk in executor.chat(chatRequest: chatRequest) {
                    if let messageChunk = chunk.message {
                        if isFirstChunk {
                            // On the first chunk, update the placeholder's creation date and initial content
                            if let index = lastAssistantMessageIndex {
                                messages[index].createdAt = chunk.createdAt
                                accumulatedContent = messageChunk.content
                                messages[index].content = accumulatedContent
                                lastUIUpdateTime = Date()
                            }
                            isFirstChunk = false
                        } else {
                            // Subsequent chunks
                            accumulatedContent += messageChunk.content
                        }

                        let now = Date()
                        let timeSinceLastUpdate = now.timeIntervalSince(lastUIUpdateTime)
                        
                        // Update UI based on buffer size or time interval
                        if let index = lastAssistantMessageIndex, (accumulatedContent.count > messages[index].content.count + updateCharacterCount || timeSinceLastUpdate > updateInterval || chunk.done) {
                            messages[index].content = accumulatedContent
                            lastUIUpdateTime = now
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics and set isStreaming to false
                        if messages.indices.contains(index) {
                            messages[index].content = accumulatedContent // Ensure final content is set
                            messages[index].totalDuration = chunk.totalDuration
                            messages[index].evalCount = chunk.evalCount
                            messages[index].evalDuration = chunk.evalDuration
                            messages[index].isStreaming = false
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
        let apiMessages = messages.prefix(userMessageIndex + 1).map { msg in
            ChatMessage(role: msg.role, content: msg.content, images: msg.images, toolCalls: msg.toolCalls, toolName: msg.toolName)
        }

        print("Retrying with API messages: \(apiMessages.map { $0.content })") // デバッグ用ログを追加

        guard let model = selectedModel else {
            errorMessage = "Please select a model first."
            return
        }

        let chatRequest = ChatRequest(model: model.name, messages: Array(apiMessages), stream: true, options: nil, tools: nil)

        // Add a placeholder for the assistant's response
        let placeholderMessage = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        messages.append(placeholderMessage)
        let assistantMessageId = placeholderMessage.id

        isStreaming = true // 全体のストリーミング状態をtrueに設定

        Task {
            let lastAssistantMessageIndex: Int? = messages.firstIndex(where: { $0.id == assistantMessageId })
            var accumulatedContent = ""
            var lastUIUpdateTime = Date()
            let updateInterval = 0.1 // 100ms
            let updateCharacterCount = 20 // 20文字ごと
            var isFirstChunk = true

            do {
                for try await chunk in executor.chat(chatRequest: chatRequest) {
                    if let messageChunk = chunk.message {
                        if isFirstChunk {
                            // On the first chunk, update the placeholder's creation date and initial content
                            if let index = lastAssistantMessageIndex {
                                messages[index].createdAt = chunk.createdAt
                                accumulatedContent = messageChunk.content
                                messages[index].content = accumulatedContent
                                lastUIUpdateTime = Date()
                            }
                            isFirstChunk = false
                        } else {
                            // Subsequent chunks
                            accumulatedContent += messageChunk.content
                        }

                        let now = Date()
                        let timeSinceLastUpdate = now.timeIntervalSince(lastUIUpdateTime)

                        // Update UI based on buffer size or time interval
                        if let index = lastAssistantMessageIndex, (accumulatedContent.count > messages[index].content.count + updateCharacterCount || timeSinceLastUpdate > updateInterval || chunk.done) {
                            messages[index].content = accumulatedContent
                            lastUIUpdateTime = now
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics and set isStreaming to false
                        if messages.indices.contains(index) {
                            messages[index].content = accumulatedContent // Ensure final content is set
                            messages[index].totalDuration = chunk.totalDuration
                            messages[index].evalCount = chunk.evalCount
                            messages[index].evalDuration = chunk.evalDuration
                            messages[index].isStreaming = false
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
                    ForegroundColor(message.role == "user" ? .white : .primary)
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
                        let tokensPerSecond = Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
                        Text(String(format: "%.2f tok/s", tokensPerSecond))
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

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}


