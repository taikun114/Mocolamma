import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var executor: CommandExecutor
    @State private var selectedModel: OllamaModel?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var showingModelSelectionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Model Selection Header
            HStack {
                Text("Selected Model:")
                    .font(.headline)
                Button(action: {
                    showingModelSelectionSheet = true
                }) {
                    Text(selectedModel?.name ?? "Select Model")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle()) // ボタンのスタイルをリセット
                .popover(isPresented: $showingModelSelectionSheet, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                    ModelSelectionSheet(selectedModel: $selectedModel, models: executor.models)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            // Chat Messages Display
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessageId = messages.last?.id {
                        scrollViewProxy.scrollTo(lastMessageId, anchor: .bottom)
                    }
                }

                // Message Input
                HStack {
                    TextField("Type your message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending || selectedModel == nil)

                    if isSending {
                        ProgressView()
                    }

                    Button(action: { sendMessage(scrollViewProxy: scrollViewProxy) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(inputText.isEmpty || isSending || selectedModel == nil ? .gray : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || isSending || selectedModel == nil)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
            } // End of ScrollViewReader
        } // End of VStack for body
        .navigationTitle("Chat")
        .toolbar {
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
        .onAppear {
            // 初期モデルの選択 (もしあれば)
            if selectedModel == nil, let firstModel = executor.models.first {
                selectedModel = firstModel
            }
        }
        .onChange(of: executor.models) { _, newModels in
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

    private func sendMessage(scrollViewProxy: ScrollViewProxy) {
        guard let model = selectedModel else {
            errorMessage = "Please select a model first."
            return
        }
        guard !inputText.isEmpty else { return }

        isSending = true
        let userMessageContent = inputText
        inputText = "" // Clear input field immediately

        // Add user message to chat history
        let userMessage = ChatMessage(role: "user", content: userMessageContent, createdAt: ISO8601DateFormatter().string(from: Date()))
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
                            var newAssistantMessage = ChatMessage(role: messageChunk.role, content: messageChunk.content)
                            newAssistantMessage.createdAt = chunk.createdAt // Set createdAt from the first chunk
                            messages.append(newAssistantMessage)
                            assistantMessageId = newAssistantMessage.id
                            lastAssistantMessageIndex = messages.count - 1
                            scrollViewProxy.scrollTo(newAssistantMessage.id, anchor: .bottom)
                        } else if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            // Append content to existing assistant message
                            messages[index].content += messageChunk.content
                            lastAssistantMessageIndex = index
                            scrollViewProxy.scrollTo(messages[index].id, anchor: .bottom)
                        }
                    }

                    if chunk.done, let index = lastAssistantMessageIndex {
                        // Final chunk, update performance metrics
                        messages[index].totalDuration = chunk.totalDuration
                        messages[index].evalCount = chunk.evalCount
                        messages[index].evalDuration = chunk.evalDuration
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

    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading) {
            Markdown(message.content)
                .padding(10)
                .background(message.role == "user" ? Color.blue : Color.gray.opacity(0.1))
                .cornerRadius(15)
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
            
            if message.role == "assistant" && isHovering {
                HStack {
                    Text(dateFormatter.string(from: ISO8601DateFormatter().date(from: message.createdAt ?? "") ?? Date()))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let evalCount = message.evalCount, let evalDuration = message.evalDuration, evalDuration > 0 {
                        let tokensPerSecond = Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
                        Text(String(format: "%.2f tok/s", tokensPerSecond))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
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

// MARK: - ModelSelectionSheet

struct ModelSelectionSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedModel: OllamaModel?
    let models: [OllamaModel]

    var body: some View {
        List(models, id: \.id) { model in
            Button(action: {
                selectedModel = model
                dismiss()
            }) {
                HStack {
                    Text(model.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(model.name)
                    Spacer()
                    if selectedModel?.id == model.id {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .listStyle(.plain)
        .background(Color.clear)
        .navigationTitle("Select a Model")
    }
}
