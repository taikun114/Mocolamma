import SwiftUI
import MarkdownUI

struct MessageView: View {
    @ObservedObject var message: ChatMessage
    let isLastAssistantMessage: Bool
    let isLastOwnUserMessage: Bool
    let onRetry: ((UUID, ChatMessage) -> Void)?
    @Binding var isStreamingAny: Bool
    @Binding var allMessages: [ChatMessage]
    let isModelSelected: Bool
    @State private var isHovering: Bool = false
    @State private var isEditing: Bool = false
    @FocusState private var isEditingFocused: Bool
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
                .background(message.role == "user" ? Color.accentColor : Color.gray.opacity(0.1))
                .cornerRadius(16)
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack {
                EmptyView()
            }
            .id(isStreamingAny)
            
            #if os(iOS)
            Spacer().frame(height: 8)
            #endif
            Group {
                #if os(iOS)
                VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 2) {
                    HStack {
                        if message.role == "user" { Spacer() }
                        Text(dateString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if message.role == "assistant" { tokenAndSpeed }
                        if message.role == "assistant" { Spacer() }
                    }
                    HStack(spacing: 6) {
                        if message.role == "user" { Spacer() }
                        if message.role == "assistant" && isLastAssistantMessage && !message.revisions.isEmpty { revisionNavigator }
                        if message.role == "assistant" && isLastAssistantMessage && ((!message.isStreaming || message.isStopped) && !isStreamingAny) { retryButton }
                        if (message.role == "assistant" || message.role == "user") && (!message.isStreaming || message.isStopped) { copyButton }
                        if message.role == "user" && isLastOwnUserMessage && ((!message.isStreaming || message.isStopped) && !isStreamingAny) {
                            if isEditing { cancelButton; doneButton } else { editButton }
                        }
                        if message.role == "assistant" { Spacer() }
                    }
                }
                #else
                HStack {
                    if message.role == "user" {
                        Spacer()
                    }
                    Text(dateString)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if message.role == "assistant" {
                        tokenAndSpeed
                    }

                    if message.role == "assistant" && isLastAssistantMessage && !message.revisions.isEmpty {
                        revisionNavigator
                    }

                    if message.role == "assistant" && isLastAssistantMessage && (!message.isStreaming || message.isStopped) {
                        retryButton
                    }

                    if (message.role == "assistant" || message.role == "user") && (!message.isStreaming || message.isStopped) {
                        copyButton
                    }

                    if message.role == "user" && isLastOwnUserMessage && (!message.isStreaming || message.isStopped) {
                        if isEditing {
                            cancelButton
                            doneButton
                        } else {
                            editButton
                        }
                    }

                    if message.role == "assistant" {
                        Spacer()
                    }
                }
                #endif
            }
            #if os(macOS)
            .opacity((isHovering && (!message.isStreaming || message.isStopped)) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            #else
            .opacity(1.0)
            #endif
            .onChange(of: isEditing) { _, _ in withAnimation { } } // isEditing用にこのonChangeを保持
        }
        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
        #if os(macOS)
        .padding(message.role == "user" ? .leading : .trailing, 64)
        #else
        .padding(message.role == "user" ? .leading : .trailing, 0)
        #endif
        .contentShape(Rectangle())
         #if os(macOS)
         .onHover { isHovering = $0 }
         #endif
    }

    private var dateString: String {
        dateFormatter.string(from: {
            if let createdAtString = message.createdAt,
               let createdAtDate = MessageView.iso8601Formatter.date(from: createdAtString) {
                if message.role == "assistant", !message.isStopped, let evalDuration = message.evalDuration {
                    return createdAtDate.addingTimeInterval(Double(evalDuration) / 1_000_000_000.0)
                } else {
                    return createdAtDate
                }
            }
            return Date()
        }())
    }

    @ViewBuilder
    private var tokenAndSpeed: some View {
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

    @ViewBuilder
    private var revisionNavigator: some View {
        Group { // ビュービルダー全体にdisabled修飾子を適用するためにGroupでラップ
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

                message.fixedContent = message.content
                message.pendingContent = ""
                message.fixedThinking = message.thinking ?? ""
                message.pendingThinking = ""
            }) {
                Image(systemName: "chevron.backward")
                    .contentShape(Rectangle())
                    .padding(5)
            }
            #if os(iOS)
            .font(.body)
            #else
            .font(.caption2)
            #endif
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
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
                message.fixedContent = message.content
                message.pendingContent = ""
                message.fixedThinking = message.thinking ?? ""
                message.pendingThinking = ""
            }) {
                Image(systemName: "chevron.forward")
                    .contentShape(Rectangle())
                    .padding(5)
            }
            #if os(iOS)
            .font(.body)
            #else
            .font(.caption2)
            #endif
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help("Next Revision")
            .disabled(message.currentRevisionIndex == message.revisions.count)
        }
        .disabled(isStreamingAny)
    }

    @ViewBuilder
    private var retryButton: some View {
        Button(action: {
            onRetry?(message.id, message)
        }) {
            Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                .contentShape(Rectangle())
                .padding(5)
        }
        #if os(iOS)
        .font(.body)
        #else
        .font(.caption2)
        #endif
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help("Retry")
        .disabled(!isModelSelected)
    }

    @ViewBuilder
    private var copyButton: some View {
        Button(action: {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            var contentToCopy = message.content
            if let thinking = message.thinking, !thinking.isEmpty {
                contentToCopy = "<think>\(thinking)</think>\n" + message.content
            }
            pasteboard.setString(contentToCopy, forType: .string)
            #else
            var contentToCopy = message.content
            if let thinking = message.thinking, !thinking.isEmpty {
                contentToCopy = "<think>\(thinking)</think>\n" + message.content
            }
            UIPasteboard.general.string = contentToCopy
            #endif
        }) {
            Image(systemName: "document.on.document")
                .contentShape(Rectangle())
                .padding(5)
        }
        #if os(iOS)
        .font(.body)
        #else
        .font(.caption2)
        #endif
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help("Copy")
    }

        @ViewBuilder
    private var editButton: some View {
        Group {
            Button(action: {
                isEditing = true
                isEditingFocused = true
                message.content = message.content
            }) {
                Image(systemName: "pencil")
                    .contentShape(Rectangle())
                    .padding(5)
            }
            #if os(iOS)
            .font(.body)
            #else
            .font(.caption2)
            #endif
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help("Edit")
            .disabled(isStreamingAny)
        }
        .id(isStreamingAny)
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: {
            isEditing = false
            message.content = message.fixedContent
        }) {
            Label { Text("Cancel") } icon: { Image(systemName: "xmark") }
                #if os(iOS)
                .font(.body)
                #else
                .font(.caption2)
                #endif
                .bold()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.gray.opacity(0.2)))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Cancel editing."))
        .disabled(message.isStreaming)
    }

    @ViewBuilder
    private var doneButton: some View {
        Button(action: {
            isEditing = false
            message.fixedContent = message.content
            message.pendingContent = ""
            onRetry?(message.id, message)
        }) {
            Label { Text("Done") } icon: { Image(systemName: "checkmark") }
                #if os(iOS)
                .font(.body)
                #else
                .font(.caption2)
                #endif
                .bold()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Complete editing and retry."))
        .disabled(!isModelSelected || isStreamingAny || message.content.isEmpty)
        .allowsHitTesting(!isStreamingAny)
        .transaction { $0.disablesAnimations = true }
        .id(isStreamingAny ? "on" : "off")
    }

    @ViewBuilder
    private var messageContentView: some View {
        if isEditing && message.role == "user" {
            VStack(alignment: .trailing) {
                TextField("Type your message...", text: $message.content, axis: .vertical)
                    .focused($isEditingFocused)
                    .onChange(of: isEditingFocused) { _, focused in
                        if focused {
                            message.content = message.content + ""
                        }
                    }
                    .onAppear { if isEditingFocused { } }
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background.secondary.opacity(0.7))
                     .cornerRadius(8)
                     .onKeyPress(KeyEquivalent.return) {
                         #if os(macOS)
                         if NSEvent.modifierFlags.contains(.command) {
                             Task { @MainActor in
                                 isEditing = false
                                 message.fixedContent = message.content
                                 message.pendingContent = ""
                                 onRetry?(message.id, message)
                             }
                             return .handled
                         } else {
                             Task { @MainActor in
                                 message.content += "\n"
                             }
                             return .handled
                         }
                         #else
                         Task { @MainActor in
                             message.content += "\n"
                         }
                         return .handled
                         #endif
                     }
             }
         } else if !(message.fixedThinking.isEmpty && message.pendingThinking.isEmpty) {
            VStack(alignment: .leading) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        if !message.fixedThinking.isEmpty {
                            Text(message.fixedThinking)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        if !message.pendingThinking.isEmpty {
                            Text(message.pendingThinking)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } label: {
                    Label(message.isThinkingCompleted ? "Thinking completed" : "Thinking...", systemImage: "brain.filled.head.profile")
                        .foregroundColor(.secondary)
                        .symbolEffect(.pulse, isActive: message.isStreaming && !message.isThinkingCompleted)
                }
                .padding(.bottom, 4)

                streamingContentBody
            }
        } else {
            streamingContentBody
        }
    }

    @ViewBuilder
    private var streamingContentBody: some View {
        if message.isStreaming && message.fixedContent.isEmpty && message.pendingContent.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(2)
        } else if message.isStopped && (message.fixedContent + message.pendingContent).isEmpty {
            Text("*No message*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if !message.isStreaming && (message.fixedContent + message.pendingContent).isEmpty {
            Text("*Could not connect*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.fixedContent.isEmpty {
                    Markdown(message.fixedContent)
                        .markdownTheme(Theme.simple(for: message))
                }
                if !message.pendingContent.isEmpty {
                    Text(message.pendingContent)
                        .font(.body)
                        .foregroundColor(message.role == "user" ? .white : .primary)
                        .fixedSize(horizontal: false, vertical: true)
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

extension Theme {
    static func simple(for message: ChatMessage) -> Theme {
        Theme()
            .text {
                ForegroundColor(message.role == "user" ? .white : nil)
            }
            .strong {
                FontWeight(.bold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(message.role == "user" ? .white : nil)
                UnderlineStyle(.single)
            }
            .code {
                FontFamilyVariant(.monospaced)
                BackgroundColor(message.role == "user" ? .white.opacity(0.2) : .gray.opacity(0.2))
            }

            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(2.0))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.75))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.5))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.25))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.0))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(0.8))
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .zero, bottom: .em(0.8))
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.3))
            }
            .blockquote { configuration in
                configuration.label
                    .padding()
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(message.role == "user" ? .white : .gray)
                            .frame(width: 4)
                    }
            }
            .codeBlock { configuration in
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
            .tableCell { configuration in
                configuration.label
                    .padding(8)
            }
            .table { configuration in
                configuration.label
                    .padding(.bottom, 8)
            }
    }
}
