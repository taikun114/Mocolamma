import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
    @EnvironmentObject var serverManager: ServerManager
    @State private var selectedModel: OllamaModel?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
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
            ChatMessagesView(messages: $messages)

            VStack {
                
                Spacer()
                ChatInputView(inputText: $inputText, isSending: $isSending, selectedModel: selectedModel) {
                    sendMessage()
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
                isSending = false
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

        isSending = true
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

        Task {
            var assistantMessageId: UUID?
            var lastAssistantMessageIndex: Int?

            do {
                for try await chunk in executor.chat(chatRequest: chatRequest) {
                    if let messageChunk = chunk.message {
                        if assistantMessageId == nil {
                            // First chunk for a new assistant message
                            var newAssistantMessage = ChatMessage(role: messageChunk.role, content: messageChunk.content, isStreaming: true)
                            newAssistantMessage.createdAt = chunk.createdAt // Set createdAt from the first chunk
                            messages.append(newAssistantMessage)
                            assistantMessageId = newAssistantMessage.id
                            lastAssistantMessageIndex = messages.count - 1
                            
                            
                        } else if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            // Append content to existing assistant message
                            messages[index].content += messageChunk.content
                            lastAssistantMessageIndex = index

                            // UI更新のバッファリング
                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) > 0.1 || chunk.done {
                                lastUpdateTime = now
                                // Force UI update by re-assigning messages array
                                messages = messages
                            }
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics and set isStreaming to false
                        messages[index].totalDuration = chunk.totalDuration
                        messages[index].evalCount = chunk.evalCount
                        messages[index].evalDuration = chunk.evalDuration
                        messages[index].isStreaming = false
                    }
                }
            } catch {
                errorMessage = "Chat API Error: \(error.localizedDescription)"
                print("Chat API Error: \(error)")
            }
            isSending = false
        }
    }
}

// MARK: - MessageView

struct MessageView: View {
    let message: ChatMessage
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
            Markdown(message.content)
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
                        .fill(Color.gray)
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
                        if message.role == "assistant", let evalDuration = message.evalDuration {
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

                if message.role == "assistant", let evalCount = message.evalCount, let evalDuration = message.evalDuration, evalDuration > 0 {
                    let tokensPerSecond = Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
                    Text(String(format: "%.2f tok/s", tokensPerSecond))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if message.role == "assistant" {
                    Spacer()
                }
            }
            .opacity(isHovering && !message.isStreaming ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
        .padding(.horizontal, 5)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}


