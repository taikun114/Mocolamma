import SwiftUI
import Textual
import UniformTypeIdentifiers
import Photos

struct MessageView: View {
    @Environment(CommandExecutor.self) var executor
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // 保存関連の状態
    @State private var showingSaveOptions = false
    @State private var showingFileExporter = false
    @State private var imageDocument: ImageDocument?
    
    private var isDownloadSuccessful: Bool {
        executor.successfullyDownloadedIDs.contains(message.id)
    }
    
    private var isCopied: Bool {
        executor.successfullyCopiedIDs.contains(message.id)
    }
    
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
                        if message.isImageGeneration && message.generatedImage != nil { downloadButton }
                        if (message.role == "assistant" || message.role == "user") && (!message.isStreaming || message.isStopped) && !message.isImageGeneration { copyButton }
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
                    
                    if message.isImageGeneration && message.generatedImage != nil {
                        downloadButton
                    }
                    
                    if (message.role == "assistant" || message.role == "user") && (!message.isStreaming || message.isStopped) && !message.isImageGeneration {
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
        .padding(message.role == "user" ? .leading : .trailing, (horizontalSizeClass == .regular) ? 64 : 0)
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
        } else if message.isImageGeneration {
            if let duration = message.totalDuration {
                Text(formatDuration(nanoseconds: duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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
    
    private func formatDuration(nanoseconds: Int) -> String {
        let totalSeconds = Int(round(Double(nanoseconds) / 1_000_000_000.0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        var parts: [String] = []
        
        if hours > 0 {
            parts.append(String(format: NSLocalizedString("%dh", comment: "Duration hours (English)"), hours))
        }
        
        if minutes > 0 || hours > 0 {
            parts.append(String(format: NSLocalizedString("%dm", comment: "Duration minutes (English)"), minutes))
        }
        
        parts.append(String(format: NSLocalizedString("%ds", comment: "Duration seconds (English)"), seconds))
        
        // 日本語環境の場合の特殊処理（もしxcstringsだけで解決できない場合のため）
        // ただし、本来は xcstrings で "%dh" を "%d時間" に翻訳するのがベストプラクティスです。
        return parts.joined(separator: " ")
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
                message.generatedImage = revision.generatedImage
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
                    message.generatedImage = revision.generatedImage
                } else {
                    message.content = message.latestContent ?? ""
                    message.thinking = message.finalThinking
                    message.isThinkingCompleted = message.finalIsThinkingCompleted
                    message.createdAt = message.finalCreatedAt
                    message.totalDuration = message.finalTotalDuration
                    message.evalCount = message.finalEvalCount
                    message.evalDuration = message.finalEvalDuration
                    message.isStopped = message.finalIsStopped
                    message.generatedImage = message.latestGeneratedImage
                }
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
            Image(systemName: SFSymbol.retry)
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
    private var downloadButton: some View {
        Button(action: {
            showingSaveOptions = true
        }) {
            Image(systemName: isDownloadSuccessful ? "checkmark" : "arrow.down.to.line")
                .contentShape(Rectangle())
                .padding(5)
                .symbolVariant(isDownloadSuccessful ? .none : .none) // 整合性のための指定
                .contentTransition(.symbolEffect(.replace))
        }
#if os(iOS)
        .font(.body)
#else
        .font(.caption2)
#endif
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help("Download Image")
        .confirmationDialog(Text("Select Destination"), isPresented: $showingSaveOptions, titleVisibility: .visible) {
            Button(String(localized: "Save to Photo Library")) {
                saveToPhotoLibrary()
            }
            Button(String(localized: "Save as File...")) {
                prepareForFileSave()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Please select where to save this image.")
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: imageDocument,
            contentType: .png,
            defaultFilename: "generated_image.png"
        ) { result in
            switch result {
            case .success(let url):
                print("Image saved to: \(url.path)")
                showSuccessFeedback()
            case .failure(let error):
                print("Failed to save image: \(error.localizedDescription)")
            }
        }
    }
    
    private func showSuccessFeedback() {
        Task { @MainActor in
            withAnimation(.spring()) {
                _ = executor.successfullyDownloadedIDs.insert(message.id)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.spring()) {
                _ = executor.successfullyDownloadedIDs.remove(message.id)
            }
        }
    }
    
    private func saveToPhotoLibrary() {
        guard let base64String = message.generatedImage,
              let data = Data(base64Encoded: base64String),
              let image = PlatformImage(data: data) else { return }
        
#if os(macOS)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("Photos access denied: \(status)")
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            do {
                try data.write(to: tempURL)
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                } completionHandler: { success, error in
                    Task { @MainActor in
                        if success {
                            print("Successfully saved to Photos")
                            showSuccessFeedback()
                        } else {
                            print("Error saving to Photos: \(error?.localizedDescription ?? "Unknown error")")
                        }
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }
            } catch {
                print("Failed to create temp file for Photos: \(error.localizedDescription)")
            }
        }
#else
        let imageSaver = ImageSaver()
        imageSaver.onSuccess = {
            showSuccessFeedback()
        }
        imageSaver.writeToPhotoAlbum(image: image)
#endif
    }
    
    private func prepareForFileSave() {
        guard let base64String = message.generatedImage,
              let data = Data(base64Encoded: base64String) else { return }
        
#if os(macOS)
        // アクションシートが閉じるのを待つための遅延
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.nameFieldStringValue = "generated_image.png"
            
            if let window = NSApp.keyWindow {
                savePanel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = savePanel.url {
                        do {
                            try data.write(to: url)
                            showSuccessFeedback()
                        } catch {
                            print("Failed to save file: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        do {
                            try data.write(to: url)
                            showSuccessFeedback()
                        } catch {
                            print("Failed to save file: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
#else
        self.imageDocument = ImageDocument(image: data)
        self.showingFileExporter = true
#endif
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
            showCopyFeedback()
        }) {
            Image(systemName: isCopied ? "checkmark" : SFSymbol.copy)
                .contentShape(Rectangle())
                .padding(5)
                .contentTransition(.symbolEffect(.replace))
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
    
    private func showCopyFeedback() {
        Task { @MainActor in
            withAnimation(.spring()) {
                _ = executor.successfullyCopiedIDs.insert(message.id)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.spring()) {
                _ = executor.successfullyCopiedIDs.remove(message.id)
            }
        }
    }
    
    private func copyImageToClipboard(image: PlatformImage) {
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
#else
        UIPasteboard.general.image = image
#endif
        showCopyFeedback()
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
        }) {
            Label { Text("Cancel") } icon: { Image(systemName: "xmark") }
#if os(iOS)
                .font(.body)
                .bold()
#else
                .font(.caption2)
                .bold()
#endif
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
            onRetry?(message.id, message)
        }) {
            Label { Text("Done") } icon: { Image(systemName: "checkmark") }
#if os(iOS)
                .font(.body)
                .bold()
#else
                .font(.caption2)
                .bold()
#endif
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
                                onRetry?(message.id, message)
                            }
                            return .handled
                        } else {
                            // Commandキーが押されていない場合はonSubmitに処理を委譲
                            return .ignored
                        }
#else
                        // iOSではonKeyPressを削除し、onSubmitに処理を委譲
                        return .ignored
#endif
                    }
                    .onSubmit { // onSubmitで改行を挿入するように変更
                        // 変換確定後にEnterが押されたら改行を挿入
                        message.content += "\n"
                    }
            }
        } else if message.isImageGeneration && message.role == "assistant" {
            VStack(alignment: .leading, spacing: 10) {
                if let base64String = message.generatedImage,
                   let data = Data(base64Encoded: base64String),
                   let image = PlatformImage(data: data) {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .contextMenu {
                            Button {
                                copyImageToClipboard(image: image)
                            } label: {
                                Label(String(localized: "Copy Image"), systemImage: SFSymbol.copy)
                            }
                        }
                        .draggable(Image(platformImage: image))
                } else if message.isStreaming {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                        
                        if let completed = message.imageProgressCompleted, let total = message.imageProgressTotal {
                            ProgressView(value: Double(completed), total: Double(total))
                                .progressViewStyle(.linear)
                            Text("\(completed) / \(total)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Generating image...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if message.content == "*Cancelled*" {
                    Text("*Cancelled*")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !message.content.isEmpty {
                    let displayContent = (message.role == "assistant" && message.isStreaming && !message.isStopped)
                        ? message.content.replacingOccurrences(of: #"(?m)^```[^\s\n]+\s*\n"#, with: "```\n", options: [.regularExpression])
                        : message.content
                    StructuredText(markdown: displayContent)
                        .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                        .textual.structuredTextStyle(SimpleStyle(message: message))
                        .textual.textSelection(.enabled)
                        .textual.overflowMode(.scroll)
                        .compositingGroup() // 描画を最適化
                } else {
                    Text("Failed to generate image.")
                        .foregroundColor(.red)
                }
            }
        } else if !(message.thinking ?? "").isEmpty {
            VStack(alignment: .leading) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        if let thinking = message.thinking, !thinking.isEmpty {
                            Text(thinking)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
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
        if message.isStreaming && message.content.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(2)
        } else if message.isStopped && message.content.isEmpty {
            Text("*No message*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if !message.isStreaming && message.content.isEmpty {
            Text("*Could not connect*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                let displayContent = (message.role == "assistant" && message.isStreaming && !message.isStopped)
                    ? message.content.replacingOccurrences(of: #"(?m)^```[^\s\n]+\s*\n"#, with: "```\n", options: [.regularExpression])
                    : message.content
                StructuredText(markdown: displayContent)
                    .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                    .textual.structuredTextStyle(SimpleStyle(message: message))
                    .textual.textSelection(.enabled)
                    .textual.overflowMode(.scroll)
                    .compositingGroup() // 描画を最適化
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

// MARK: - Textual Custom Style

struct SimpleStyle: StructuredText.Style {
    let message: ChatMessage

    var inlineStyle: InlineStyle {
        InlineStyle()
            .strong(.bold)
            .emphasis(.italic)
            .link(
                .foregroundColor(message.role == "user" ? Color.white : Color.accentColor),
                .underlineStyle(.single)
            )
            .code(
                .monospaced,
                .backgroundColor(message.role == "user" ? Color.white.opacity(0.2) : Color.gray.opacity(0.2))
            )
    }

    var headingStyle: some StructuredText.HeadingStyle {
        SimpleHeadingStyle()
    }

    var paragraphStyle: some StructuredText.ParagraphStyle {
        SimpleParagraphStyle()
    }

    var blockQuoteStyle: some StructuredText.BlockQuoteStyle {
        SimpleBlockQuoteStyle(message: message)
    }

    var codeBlockStyle: some StructuredText.CodeBlockStyle {
        SimpleCodeBlockStyle(message: message)
    }

    var listItemStyle: some StructuredText.ListItemStyle {
        SimpleListItemStyle()
    }

    var unorderedListMarker: some StructuredText.UnorderedListMarker {
        StructuredText.SymbolListMarker.disc
    }

    var orderedListMarker: some StructuredText.OrderedListMarker {
        StructuredText.DecimalListMarker.decimal
    }

    var tableStyle: some StructuredText.TableStyle {
        SimpleTableStyle(message: message)
    }

    var tableCellStyle: some StructuredText.TableCellStyle {
        SimpleTableCellStyle()
    }

    var thematicBreakStyle: some StructuredText.ThematicBreakStyle {
        StructuredText.DividerThematicBreakStyle.divider
    }
}

struct SimpleListItemStyle: StructuredText.ListItemStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.block
    }
}

struct SimpleTableStyle: StructuredText.TableStyle {
    let message: ChatMessage
    private static let borderWidth: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: Self.borderWidth, vertical: Self.borderWidth)
            .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 1.6))
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(
                            Path(divider),
                            with: .style(message.role == "user" ? Color.white.opacity(0.4) : Color.gray.opacity(0.4))
                        )
                    }
                }
            }
            .padding(Self.borderWidth)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(message.role == "user" ? Color.white.opacity(0.4) : Color.gray.opacity(0.4), lineWidth: Self.borderWidth)
            }
    }
}

struct SimpleHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [2.0, 1.75, 1.5, 1.25, 1.0, 0.8]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let fontScale = Self.fontScales[level - 1]

        configuration.label
            .textual.fontScale(fontScale)
            .fontWeight(.bold)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct SimpleParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.3))
            .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.8))
    }
}

struct SimpleBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    let message: ChatMessage

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(message.role == "user" ? Color.white : Color.gray)
                    .frame(width: 4)
            }
    }
}

struct SimpleCodeBlockStyle: StructuredText.CodeBlockStyle {
    let message: ChatMessage

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー: 言語名
            HStack {
                Text(formatLanguageName(configuration.languageHint))
                    .font(.caption2.monospaced())
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.05))

            Divider()
                .opacity(0.5)

            // コード本体
            Overflow {
                configuration.label
                    .monospaced()
                    .textual.lineSpacing(.fontScaled(0.39))
                    .padding()
            }
        }
        .background(message.role == "user" ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 8)
        .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.8))
    }

    private func formatLanguageName(_ hint: String?) -> String {
        guard let hint = hint?.lowercased() else {
            return String(localized: "Code")
        }

        // 特定の言語名の正式な表記マッピング（途中に大文字が入るものや記号を含むもの）
        let specialCases: [String: String] = [
            "javascript": "JavaScript",
            "typescript": "TypeScript",
            "csharp": "C#",
            "php": "PHP",
            "sql": "SQL",
            "json": "JSON",
            "html": "HTML",
            "css": "CSS",
            "xml": "XML",
            "yaml": "YAML",
            "csv": "CSV",
            "cpp": "C++",
            "cplusplus": "C++",
            "objectivec": "Objective-C"
        ]

        if let specialName = specialCases[hint] {
            return specialName
        }

        // 1文字の場合は大文字にする (例: "r" -> "R")
        if hint.count == 1 {
            return hint.uppercased()
        }

        // それ以外は先頭を大文字にする (例: "swift" -> "Swift", "markdown" -> "Markdown")
        return hint.prefix(1).uppercased() + hint.dropFirst()
    }
}

struct SimpleTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .textual.textSelection(.enabled)
    }
}


// MARK: - Platform Compatibility & Document Support

#if os(macOS)
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}

class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?

    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveError), nil)
    }

    @objc func saveError(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("Error saving image: \(error.localizedDescription)")
        } else {
            print("Successfully saved image to photo album.")
            onSuccess?()
        }
    }
}
#endif

struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var image: Data

    init(image: Data) {
        self.image = image
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            self.image = data
        } else {
            throw CocoaError(.fileReadUnknown)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: image)
    }
}

