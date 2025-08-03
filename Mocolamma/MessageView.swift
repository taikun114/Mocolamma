import SwiftUI
import MarkdownUI

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
                            contentToCopy = "<think>\(thinking)</think>\n" + message.content
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
        .onHover {
            isHovering = $0
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
