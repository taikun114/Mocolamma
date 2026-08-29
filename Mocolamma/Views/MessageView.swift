import SwiftUI
import Textual
import UniformTypeIdentifiers
import Photos
import PhotosUI

struct MessageView: View {
    @Environment(ChatSettings.self) var chatSettings
    var message: ChatMessage
    let isLastAssistantMessage: Bool
    let isLastOwnUserMessage: Bool
    let selectedModelName: String?
    let onRetry: ((UUID, ChatMessage) -> Void)?
    let onPreviewImage: ((PlatformImage) -> Void)?
    @Binding var isStreamingAny: Bool
    let isModelSelected: Bool
    @State private var isHovering: Bool = false
    @State private var isEditing: Bool = false
    @FocusState private var isEditingFocused: Bool
    @State private var showingVisionWarningAlert = false
    @State private var showingVisionPDFWarningAlert = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.containerHeight) private var containerHeight
    
    // 編集用画像および添付ファイルの状態
    @State private var editingImages: [ChatInputImage] = []
    @State private var editingAttachments: [ChatInputAttachment] = []
    @State private var showingAttachSheet = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var draggingItem: ChatInputImage?
    @State private var draggingAttachment: ChatInputAttachment?
    @State private var isDraggingOver = false
    @State private var showingUnsupportedFileAlert = false
    @State private var unsupportedFileAlertTitle = "This file cannot be attached"
    
    // 保存関連の状態
    @State private var isSaveOptionsPresented: Bool = false
    @State private var isFileExporterPresented: Bool = false
    @State private var imageDocument: ImageDocument?
    @State private var isThinkingExpanded: Bool = false
    
    private var isDownloadSuccessful: Bool {
        message.isDownloadSuccessful
    }
    
    private var isCopied: Bool {
        message.isCopied
    }

    private var supportsVision: Bool {
        chatSettings.selectedModelCapabilities?.contains(where: { $0.lowercased() == "vision" }) ?? false
    }
    
    private var supportsCompletion: Bool {
        chatSettings.selectedModelCapabilities?.contains(where: { $0.lowercased() == "completion" }) ?? false
    }
    
    private var canAttach: Bool {
        isModelSelected && (supportsCompletion || supportsVision)
    }
    
    private var isDoneDisabled: Bool {
        guard isModelSelected && !isStreamingAny else { return true }
        let hasText = !message.content.isEmpty
        let hasAttachments = !editingAttachments.isEmpty
        let hasImages = !editingImages.isEmpty
        
        if supportsVision {
            return !hasText && !hasAttachments && !hasImages
        } else {
            return !hasText && !hasAttachments
        }
    }
    
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        return formatter
    }()
    
    static let iso8601StandardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter
    }()
    
    static func parseDate(from string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601StandardFormatter.date(from: string)
    }
    
    var body: some View {
        @Bindable var message = message
        VStack(alignment: message.role == "user" ? .trailing : .leading) {
            messageContentView
                .accessibilityElement(children: .contain)
                .accessibilityLabel(message.role == "user" ? "User message" : "Assistant message")
                .accessibilityValue(message.content)
                .padding(10)
                .background(
                    Group {
                        if message.role == "user" {
                            Color.accentColor
                        } else {
#if os(visionOS)
                            Rectangle().fill(.regularMaterial)
#else
                            Color.gray.opacity(0.1)
#endif
                        }
                    }
                )
                .cornerRadius(16)
                .overlay {
                    if isEditing && isDraggingOver {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                )
                            
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Drop here to add files")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL, .image, .text], delegate: AreaImageDropDelegate(items: $editingImages, isDraggingOver: $isDraggingOver, isEnabled: isEditing && canAttach, onURLsDropped: { urls in
                    if isEditing {
                        handleDroppedURLs(urls)
                    }
                }, onDataDropped: { data in
                    if isEditing {
                        addImages(from: data)
                    }
                }))

                .lineSpacing(4)
            
            Spacer()
                .frame(height: 0)
            
#if !os(macOS)
            Spacer().frame(height: 8)
#endif
            Group {
#if os(visionOS)
                HStack(alignment: .center, spacing: 8) {
                    if message.role == "user" { Spacer() }
                    
                    Text(dateString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if message.role == "assistant" { tokenAndSpeed }
                    
                    HStack(spacing: 6) {
                        if message.role == "assistant" && isLastAssistantMessage && !message.revisions.isEmpty { revisionNavigator }
                        if message.role == "assistant" && isLastAssistantMessage {
                            retryButton
                                .opacity((!message.isStreaming || message.isStopped) && !isStreamingAny ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if (message.role == "assistant" || message.role == "user") {
                            copyButton
                                .opacity(!message.isStreaming || message.isStopped ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if message.isImageGeneration && message.generatedImage != nil { downloadButton }
                        if message.role == "assistant" {
                            shareButton
                                .opacity((!message.isStreaming || message.isStopped) && !isStreamingAny ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if message.role == "user" && isLastOwnUserMessage {
                            if isEditing {
                                cancelButton
                                doneButton
                            } else { editButton }
                        }
                    }
                    
                    if message.role == "assistant" { Spacer() }
                }
#elseif os(iOS)
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
                        if message.role == "assistant" && isLastAssistantMessage {
                            retryButton
                                .opacity((!message.isStreaming || message.isStopped) && !isStreamingAny ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if (message.role == "assistant" || message.role == "user") {
                            copyButton
                                .opacity(!message.isStreaming || message.isStopped ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if message.isImageGeneration && message.generatedImage != nil { downloadButton }
                        if message.role == "assistant" {
                            shareButton
                                .opacity((!message.isStreaming || message.isStopped) && !isStreamingAny ? 1 : 0)
                                .disabled(message.isStreaming && !message.isStopped)
                        }
                        if message.role == "user" && isLastOwnUserMessage {
                            if isEditing {
                                cancelButton
                                doneButton
                            } else { editButton }
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

                    if message.isImageGeneration && message.generatedImage != nil {
                        downloadButton
                    }

                    if message.role == "assistant" && (!message.isStreaming || message.isStopped) {
                        shareButton
                    }
                    
                    if message.role == "user" && isLastOwnUserMessage {
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
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoLibraryPicker(isPresented: $showingPhotoPicker, selectedImages: $editingImages)
#if os(macOS)
                .frame(minWidth: 500, idealWidth: 800, maxWidth: 1500, minHeight: 300, idealHeight: 550, maxHeight: 1000)
                .presentationSizing(.fitted)
#endif
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: ChatInputAttachment.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addFiles(from: urls)
            case .failure(let error):
                print("Error picking files: \(error.localizedDescription)")
            }
        }
#if os(macOS)
        .onHover { isHovering = $0 }
#endif
    }
    
    private var dateString: String {
        dateFormatter.string(from: {
            if let createdAtString = message.createdAt,
               let createdAtDate = MessageView.parseDate(from: createdAtString) {
                if message.role == "assistant", !message.isStopped, let evalDuration = message.evalDuration {
                    return createdAtDate.addingTimeInterval(Double(evalDuration) / 1_000_000_000.0)
                } else {
                    return createdAtDate
                }
            }
            return Date()
        }())
    }
    
    private func addFiles(from urls: [URL]) {
        Task {
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                
                guard let data = data else { continue }
                
                if url.pathExtension.lowercased() == "pdf" || data.isPDFData {
                    let pdfFileName = url.pathExtension.lowercased() == "pdf" ? url.lastPathComponent : "\(url.deletingPathExtension().lastPathComponent).pdf"
                    let placeholderId = UUID()
                    let task = Task<ChatInputAttachment?, Never> {
                        await ChatInputAttachment.createPDF(from: data, fileName: pdfFileName, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = editingAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingAttachments.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                } else if PlatformImage(data: data) != nil {
                    // 画像ファイルの場合: 即座にスピナー付きプレースホルダーを追加
                    let placeholderId = UUID()
                    let task = Task<ChatInputImage?, Never> {
                        await ChatInputImage.create(from: data, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = editingImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                } else if let textContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .japaneseEUC) ?? String(data: data, encoding: .utf16) {
                    let attachment = ChatInputAttachment(name: url.lastPathComponent, content: textContent)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingAttachments.append(attachment)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
    }
    
    private func handleDroppedURLs(_ urls: [URL]) {
        Task {
            var successCount = 0
            var failureCount = 0
            
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                
                guard let data = data else {
                    failureCount += 1
                    continue
                }
                
                if url.pathExtension.lowercased() == "pdf" || data.isPDFData {
                    let pdfFileName = url.pathExtension.lowercased() == "pdf" ? url.lastPathComponent : "\(url.deletingPathExtension().lastPathComponent).pdf"
                    let placeholderId = UUID()
                    let task = Task<ChatInputAttachment?, Never> {
                        await ChatInputAttachment.createPDF(from: data, fileName: pdfFileName, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = editingAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingAttachments.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    successCount += 1
                } else if PlatformImage(data: data) != nil {
                    // 画像ファイルの場合はモデルのVision対応有無に関わらず画像サムネイルとして追加
                    let placeholderId = UUID()
                    let task = Task<ChatInputImage?, Never> {
                        await ChatInputImage.create(from: data, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = editingImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    successCount += 1
                } else if supportsCompletion, let textContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .japaneseEUC) ?? String(data: data, encoding: .utf16) {
                    let attachment = ChatInputAttachment(name: url.lastPathComponent, content: textContent)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingAttachments.append(attachment)
                        }
                    }
                    successCount += 1
                } else {
                    failureCount += 1
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            
            if failureCount > 0 {
                await MainActor.run {
                    if successCount > 0 {
                        unsupportedFileAlertTitle = "Some files could not be attached"
                    } else if failureCount > 1 {
                        unsupportedFileAlertTitle = "These files cannot be attached"
                    } else {
                        unsupportedFileAlertTitle = "This file cannot be attached"
                    }
                    showingUnsupportedFileAlert = true
                }
            }
        }
    }
    
    private func addImages(from urls: [URL]) {
        addFiles(from: urls)
    }

    private func addImages(from data: [Data]) {
        Task {
            for urlData in data {
                if urlData.isPDFData {
                    let placeholderId = UUID()
                    let pdfFileName = "Document.pdf"
                    let task = Task<ChatInputAttachment?, Never> {
                        await ChatInputAttachment.createPDF(from: urlData, fileName: pdfFileName, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = editingAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingAttachments.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                } else if PlatformImage(data: urlData) != nil {
                    let placeholderId = UUID()
                    let task = Task<ChatInputImage?, Never> {
                        await ChatInputImage.create(from: urlData, id: placeholderId)
                    }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = editingImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
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
        HStack(alignment: .center, spacing: 4) {
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
            .accessibilityLabel("Previous Revision")
#if !os(macOS)
            .font(.body)
#else
            .font(.caption2)
#endif
#if os(visionOS)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
#else
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
#endif
            .help("Previous Revision")
            .disabled(message.currentRevisionIndex == 0)
            
            if message.revisions.count > 0 {
                Text("\(message.currentRevisionIndex + 1)/\(message.revisions.count + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
#if os(visionOS)
                    .padding(.horizontal, 4)
#endif
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
            .accessibilityLabel("Next Revision")
#if !os(macOS)
            .font(.body)
#else
            .font(.caption2)
#endif
#if os(visionOS)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
#else
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
#endif
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
        .accessibilityLabel("Retry")
#if !os(macOS)
        .font(.body)
#else
        .font(.caption2)
#endif
#if os(visionOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
#else
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
#endif
        .help("Retry")
        .disabled(!isModelSelected)
    }
    
    @ViewBuilder
    private var downloadButton: some View {
        Button(action: {
            isSaveOptionsPresented = true
        }) {
            Image(systemName: isDownloadSuccessful ? "checkmark" : "arrow.down.to.line")
                .contentShape(Rectangle())
                .padding(5)
                .symbolVariant(isDownloadSuccessful ? .none : .none) // 整合性のための指定
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Download Image")
#if !os(macOS)
        .font(.body)
#else
        .font(.caption2)
#endif
#if os(visionOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
#else
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
#endif
        .help("Download Image")
        .confirmationDialog(Text("Select Destination"), isPresented: $isSaveOptionsPresented, titleVisibility: .visible) {
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
            isPresented: $isFileExporterPresented,
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
                message.isDownloadSuccessful = true
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.spring()) {
                message.isDownloadSuccessful = false
            }
        }
    }
    
    private func saveToPhotoLibrary() {
        guard let base64String = message.generatedImage,
              let data = Data(base64Encoded: base64String) else { return }
        
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
    }
    
    private func prepareForFileSave() {
        guard let base64String = message.generatedImage,
              let data = Data(base64Encoded: base64String) else { return }
        
#if os(macOS)
        // アクションシートが閉じるのを待つための遅延
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
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
        self.isFileExporterPresented = true
#endif
    }
    
    @ViewBuilder
    private var copyButton: some View {
        Button(action: {
            if message.isImageGeneration, let base64String = message.generatedImage, let imageData = Data(base64Encoded: base64String), let image = PlatformImage(data: imageData) {
                copyImageToClipboard(image: image)
            } else {
#if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                var contentToCopy = message.content
                if let thinking = message.thinking, !thinking.isEmpty {
                    contentToCopy = "<think>\(thinking)</think>\n" + contentToCopy
                } else if let finalThinking = message.finalThinking, !finalThinking.isEmpty {
                    contentToCopy = "<think>\(finalThinking)</think>\n" + contentToCopy
                }
                pasteboard.setString(contentToCopy, forType: .string)
#else
                var contentToCopy = message.content
                if let thinking = message.thinking, !thinking.isEmpty {
                    contentToCopy = "<think>\(thinking)</think>\n" + contentToCopy
                } else if let finalThinking = message.finalThinking, !finalThinking.isEmpty {
                    contentToCopy = "<think>\(finalThinking)</think>\n" + contentToCopy
                }
                UIPasteboard.general.string = contentToCopy
#endif
                showCopyFeedback()
            }
        }) {
            Image(systemName: isCopied ? "checkmark" : SFSymbol.copy)
                .contentShape(Rectangle())
                .padding(5)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Copy")
#if !os(macOS)
        .font(.body)
#else
        .font(.caption2)
#endif
#if os(visionOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
#else
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
#endif
        .help("Copy")
        .disabled(message.content.isEmpty && (message.thinking?.isEmpty ?? true) && (message.finalThinking?.isEmpty ?? true) && message.generatedImage == nil)
    }
    
    private var shareButton: some View {
        Group {
            if message.isImageGeneration, let base64String = message.generatedImage, let imageData = Data(base64Encoded: base64String), let image = PlatformImage(data: imageData) {
                ShareLink(item: Image(platformImage: image), preview: SharePreview(message.content, image: Image(platformImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                        .contentShape(Rectangle())
                        .padding(5)
                }
            } else {
                let shareText: String = {
                    var content = message.content
                    if let thinking = message.thinking, !thinking.isEmpty {
                        content = "<think>\(thinking)</think>\n" + content
                    } else if let finalThinking = message.finalThinking, !finalThinking.isEmpty {
                        content = "<think>\(finalThinking)</think>\n" + content
                    }
                    return content
                }()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .contentShape(Rectangle())
                        .padding(5)
                }
            }
        }
#if !os(macOS)
        .font(.body)
#else
        .font(.caption2)
#endif
#if os(visionOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
#else
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
#endif
        .help("Share")
        .disabled(message.content.isEmpty && (message.thinking?.isEmpty ?? true) && (message.finalThinking?.isEmpty ?? true) && message.generatedImage == nil)
    }
    
    private func showCopyFeedback() {
        Task { @MainActor in
            withAnimation(.spring()) {
                message.isCopied = true
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.spring()) {
                message.isCopied = false
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
                editingAttachments = message.attachments ?? []
                
                // 画像を編集用にコピー
                Task {
                    if let images = message.images {
                        editingImages = await withTaskGroup(of: (Int, ChatInputImage?).self) { group in
                            for (index, base64) in images.enumerated() {
                                group.addTask {
                                    if let data = Data(base64Encoded: base64) {
                                        let thumbnail = await ChatInputImage.createThumbnail(from: data)
                                        return (index, ChatInputImage(data: data, thumbnail: thumbnail))
                                    }
                                    return (index, nil)
                                }
                            }
                            
                            var results = [(Int, ChatInputImage)]()
                            for await result in group {
                                if let img = result.1 {
                                    results.append((result.0, img))
                                }
                            }
                            return results.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
                        }
                    } else {
                        editingImages = []
                    }
                }
            }) {
                Image(systemName: "pencil")
                    .contentShape(Rectangle())
                    .padding(5)
            }
            .accessibilityLabel("Edit")
#if !os(macOS)
            .font(.body)
#else
            .font(.caption2)
#endif
#if os(visionOS)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
#else
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
#endif
            .help("Edit")
            .disabled(isStreamingAny)
        }
        }
    
    @ViewBuilder
    private var cancelButton: some View {
        Button(action: {
            isEditing = false
        }) {
            Label { Text("Cancel") } icon: { Image(systemName: "xmark") }
#if !os(macOS)
                .font(.body)
                .bold()
#else
                .font(.caption2)
                .bold()
#endif
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
#if os(visionOS)
                .bold()
#else
                .background(Capsule().fill(Color.gray.opacity(0.2)))
                .foregroundColor(.secondary)
#endif
        }
#if os(visionOS)
        .buttonStyle(.bordered)
#else
        .buttonStyle(.plain)
#endif
        .help(String(localized: "Cancel editing."))
        .disabled(message.isStreaming)
    }
    
    @ViewBuilder
    private var doneButton: some View {
        Button(action: {
            let hasPDFs = editingAttachments.contains { $0.isPDF }
            let hasImages = !editingImages.isEmpty
            
            if !supportsVision {
                if hasPDFs {
                    showingVisionPDFWarningAlert = true
                    return
                } else if hasImages {
                    showingVisionWarningAlert = true
                    return
                }
            }
            performDone()
        }) {
            Label { Text("Done") } icon: { Image(systemName: "checkmark") }
#if !os(macOS)
                .font(.body)
                .bold()
#else
                .font(.caption2)
                .bold()
#endif
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
#if os(visionOS)
                .bold()
                .foregroundStyle(.white)
#else
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                .foregroundColor(.accentColor)
#endif
        }
#if os(visionOS)
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
#else
        .buttonStyle(.plain)
#endif
        .help(String(localized: "Complete editing and retry."))
        .disabled(isDoneDisabled)
        .allowsHitTesting(!isStreamingAny)
        .transaction { $0.disablesAnimations = true }
        .alert("This model does not support images", isPresented: $showingVisionWarningAlert) {
            Button("Send") {
                performDone(skipImages: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if let modelName = selectedModelName {
                Text("The selected model \"\(modelName)\" does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            } else {
                Text("The selected model does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            }
        }
        .alert("This model does not support images", isPresented: $showingVisionPDFWarningAlert) {
            Button("Send") {
                performDone(skipImages: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if let modelName = selectedModelName {
                Text("The selected model \"\(modelName)\" does not support image recognition, so attached PDF files will only be sent as extracted text. Are you sure you want to send it as is?\n\nTip: Switching to a vision-capable model will allow it to recognize images and layouts in addition to text.")
            } else {
                Text("The selected model does not support image recognition, so attached PDF files will only be sent as extracted text. Are you sure you want to send it as is?\n\nTip: Switching to a vision-capable model will allow it to recognize images and layouts in addition to text.")
            }
        }
        .alert(
            Text(LocalizedStringKey(unsupportedFileAlertTitle)),
            isPresented: $showingUnsupportedFileAlert
        ) {
            Button("OK") { }
        } message: {
            Text("Only text, PDF, or image files (vision-capable models only) can be attached.")
        }
    }
    
    private func performDone(skipImages: Bool = false) {
        isEditing = false
        
        let rawAttachments = editingAttachments
        let rawEditingImages = editingImages
        let hasPDFs = rawAttachments.contains { $0.isPDF }
        let hasImages = !skipImages && !rawEditingImages.isEmpty
        
        message.isProcessingPDF = hasPDFs
        message.isProcessingImages = !hasPDFs && hasImages
        
        // 編集内容を反映させるためのTaskを開始
        Task {
            // PDFファイルのテキスト抽出および画像化（非同期完了を待機）
            let (processedAttachments, pdfPageImages) = await rawAttachments.resolveProcessedAttachments(renderImages: supportsVision && !skipImages)
            
            // 直接添付された画像の処理（まだリサイズ中の画像があれば完了を待機し、サムネイルを事前キャッシュ）
            var directImages: [String] = []
            if hasImages {
                directImages = await rawEditingImages.resolveBase64Images()
            }
            
            await MainActor.run {
                message.attachments = processedAttachments.isEmpty ? nil : processedAttachments
                message.images = directImages.isEmpty ? nil : directImages
                message.pdfImages = pdfPageImages.isEmpty ? nil : pdfPageImages
                message.isProcessingPDF = false
                message.isProcessingImages = false
            }
            
            onRetry?(message.id, message)
        }
    }
    
    @ViewBuilder
    private var messageContentView: some View {
        @Bindable var message = message
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
            if message.isProcessingPDF {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing PDF...")
                        .font(.caption)
                        .foregroundColor(message.role == "user" ? .white.opacity(0.8) : .secondary)
                }
                .padding(.vertical, 4)
            } else if message.isProcessingImages {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing images...")
                        .font(.caption)
                        .foregroundColor(message.role == "user" ? .white.opacity(0.8) : .secondary)
                }
                .padding(.vertical, 4)
            } else if isEditing && message.role == "user" {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(editingImages) { imageContainer in
                            ZStack(alignment: .topLeading) {
                                if imageContainer.isLoading {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 80, height: 80)
                                        .overlay {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                } else if let image = imageContainer.thumbnail {
                                    Image(platformImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
#if os(visionOS)
                                        .hoverEffect()
#endif
                                        .onTapGesture {
                                            if let fullImage = PlatformImage(data: imageContainer.data) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    onPreviewImage?(fullImage)
                                                }
                                            }
                                        }
                                }
                                
                                Button(action: {
                                    imageContainer.loadTask?.cancel()
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        editingImages.removeAll(where: { $0.id == imageContainer.id })
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                                .offset(x: -8, y: -8)
                            }
                            .padding(.top, 0)
                            .padding(.leading, 0)
                            .transition(.scale(0.5).combined(with: .opacity).combined(with: .blurReplace))
                            .onDrag {
                                self.draggingItem = imageContainer
                                return NSItemProvider(object: imageContainer.id.uuidString as NSString)
                            }
                            .onDrop(of: [.fileURL, .image, .text], delegate: ImageDropDelegate(
                                item: imageContainer,
                                items: $editingImages,
                                draggingItem: $draggingItem,
                                isDraggingOver: $isDraggingOver,
                                onURLsDropped: { handleDroppedURLs($0) },
                                onDataDropped: { addImages(from: $0) }
                            ))
                        }
                        
                        ForEach(editingAttachments) { attachment in
                            ZStack(alignment: .topLeading) {
                                FileAttachmentTileView(attachment: attachment, size: 80, isUserBubble: true)
                                
                                Button(action: {
                                    attachment.loadTask?.cancel()
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        editingAttachments.removeAll(where: { $0.id == attachment.id })
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                                .offset(x: -8, y: -8)
                            }
                            .padding(.top, 0)
                            .padding(.leading, 0)
                            .transition(.scale(0.5).combined(with: .opacity).combined(with: .blurReplace))
                            .onDrag {
                                self.draggingAttachment = attachment
                                return NSItemProvider(object: attachment.id.uuidString as NSString)
                            }
                            .onDrop(of: [.fileURL, .image, .text], delegate: AttachmentDropDelegate(
                                item: attachment,
                                items: $editingAttachments,
                                draggingItem: $draggingAttachment,
                                isDraggingOver: $isDraggingOver,
                                onURLsDropped: { handleDroppedURLs($0) },
                                onDataDropped: { addImages(from: $0) }
                            ))
                        }
                        
                        // ファイルおよび画像追加タイル
                        if canAttach {
                            Button(action: {
                                showingAttachSheet = true
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                    
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 0)
                            .padding(.leading, 0)
                            .onDrop(of: [.fileURL, .image, .text], delegate: AreaImageDropDelegate(
                                items: $editingImages,
                                isDraggingOver: $isDraggingOver,
                                isEnabled: isEditing && canAttach,
                                onURLsDropped: { handleDroppedURLs($0) },
                                onDataDropped: { addImages(from: $0) }
                            ))
                            .attachFileConfirmationDialog(
                                isPresented: $showingAttachSheet,
                                showingFilePicker: $showingFilePicker,
                                showingPhotoPicker: $showingPhotoPicker,
                                supportsCompletion: supportsCompletion,
                                supportsVision: supportsVision
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 90)
                .scrollClipDisabled()
                .onDrop(of: [.fileURL, .image, .text], delegate: AreaImageDropDelegate(items: $editingImages, isDraggingOver: $isDraggingOver, isEnabled: isEditing && canAttach, onURLsDropped: { urls in
                    if isEditing {
                        handleDroppedURLs(urls)
                    }
                }, onDataDropped: { data in
                    if isEditing {
                        addImages(from: data)
                    }
                }))
            } else if (message.images != nil && !message.images!.isEmpty) || (message.attachments != nil && !message.attachments!.isEmpty) {
                // 画像・添付ファイルの表示（収まる時はバブルを画像幅に合わせ、多い時はスクロール）
                let images = message.images ?? []
                let attachments = message.attachments ?? []
                
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, base64 in
                            MessageThumbnailImageView(base64String: base64, size: 100, onPreview: onPreviewImage)
#if os(visionOS)
                                .hoverEffect()
#endif
                        }
                        ForEach(attachments) { attachment in
                            FileAttachmentTileView(attachment: attachment, size: 100, isUserBubble: message.role == "user")
                        }
                    }
                    
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, base64 in
                                MessageThumbnailImageView(base64String: base64, size: 100, onPreview: onPreviewImage)
#if os(visionOS)
                                    .hoverEffect()
#endif
                            }
                            ForEach(attachments) { attachment in
                                FileAttachmentTileView(attachment: attachment, size: 100, isUserBubble: message.role == "user")
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                .frame(height: 100)
            }
            
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
#if os(visionOS)
                    .background(.regularMaterial)
#else
                    .background(.background.secondary.opacity(0.7))
#endif
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
                    let ratio = image.size.width / image.size.height
                    let limitedHeight = containerHeight * 0.7
                    
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(ratio, contentMode: .fit)
                        .frame(maxWidth: limitedHeight * ratio, maxHeight: limitedHeight)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onPreviewImage?(image)
                            }
                        }
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
                    let displayContent = message.content
                    StructuredText.Streaming(markdown: displayContent, isStreaming: message.isStreaming)
                        .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                        .textual.structuredTextStyle(SimpleStyle(message: message))
                        .textualSelection(enabled: true)
                        .textual.syntaxHighlightingEnabled(true)
                        .textual.overflowMode(.scroll)
                } else {
                    Text("Failed to generate image.")
                        .foregroundColor(.red)
                }
            }
        } else if !(message.thinking ?? "").isEmpty {
            VStack(alignment: .leading) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isThinkingExpanded.toggle()
                    }
                }) {
                    HStack {
                        Label(message.isThinkingCompleted ? "Thinking completed" : "Thinking...", systemImage: "brain.filled.head.profile")
                            .foregroundColor(.secondary)
                            .symbolEffect(.pulse, isActive: message.isStreaming && !message.isThinkingCompleted)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isThinkingExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isThinkingExpanded ? "Collapse thinking process" : "Expand thinking process")
                .padding(.bottom, 4)
                
                if isThinkingExpanded {
                    if let thinking = message.thinking, !thinking.isEmpty {
                        StructuredText.Streaming(markdown: thinking, isStreaming: message.isStreaming && !message.isThinkingCompleted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textual.structuredTextStyle(SimpleThinkingStyle(message: message))
                            .textualSelection(enabled: true)
                            .textual.syntaxHighlightingEnabled(true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                streamingContentBody
            }
        } else {
            streamingContentBody
        }
    }
}
    
    @ViewBuilder
    private var streamingContentBody: some View {
        if message.isStreaming && message.content.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(2)
        } else if message.role == "assistant" && message.isStopped && message.content.isEmpty {
            Text("*No message*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if message.role == "assistant" && !message.isStreaming && message.content.isEmpty {
            Text("*Could not connect*")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                let displayContent = message.content
                StructuredText.Streaming(markdown: displayContent, isStreaming: message.isStreaming)
                    .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                    .textual.structuredTextStyle(SimpleStyle(message: message))
                    .textualSelection(enabled: true)
                    .textual.syntaxHighlightingEnabled(true)
                    .textual.overflowMode(.scroll)
            }
        } else {
            EmptyView()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}

// MARK: - View Helper for Textual Selection
extension View {
    func textualSelection(enabled: Bool) -> some View {
        self.textual.textSelection(enabled)
    }
}

// MARK: - Textual Custom Style

struct SimpleStyle: StructuredText.Style {
    let message: ChatMessage

    var inlineStyle: InlineStyle {
        InlineStyle()
            .strong(.fontWeight(.black))
            .emphasis(.italic)
            .link(
                .foregroundColor(message.role == "user" ? Color.white : Color.accentColor),
                .underlineStyle(.single)
            )
            .code(
                .monospaced,
                .backgroundColor({
#if os(visionOS)
                    return Color.black.opacity(0.2)
#else
                    return message.role == "user" ? Color.white.opacity(0.2) : Color.gray.opacity(0.2)
#endif
                }())
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
        MocolammaUnorderedListMarker()
    }

    var orderedListMarker: some StructuredText.OrderedListMarker {
        MocolammaOrderedListMarker()
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

    var listSpacing: FontScaled<StructuredText.BlockSpacing> {
        .fontScaled(top: 0.8, bottom: 0.8)
    }
}

struct SimpleListItemStyle: StructuredText.ListItemStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(width: 20, height: 1)
                configuration.marker
            }
            configuration.block
        }
        .padding(.leading, -4)
    }
}

struct MocolammaUnorderedListMarker: StructuredText.UnorderedListMarker {
    func makeBody(configuration: Configuration) -> some View {
        StructuredText.SymbolListMarker.disc
            .makeBody(configuration: configuration)
            .offset(y: -3.5)
    }
}

struct MocolammaThinkingUnorderedListMarker: StructuredText.UnorderedListMarker {
    func makeBody(configuration: Configuration) -> some View {
        StructuredText.SymbolListMarker.disc
            .makeBody(configuration: configuration)
            .offset(y: -2.0)
    }
}

struct MocolammaOrderedListMarker: StructuredText.OrderedListMarker {
    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: "\(configuration.ordinal).")
            .monospacedDigit()
    }
}

struct SimpleTableStyle: StructuredText.TableStyle {
    let message: ChatMessage
    private static let borderWidth: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: Self.borderWidth, vertical: Self.borderWidth)
            .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0.8))
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
    private static let fontScales: [CGFloat] = [2.0, 1.8, 1.6, 1.4, 1.2, 1.0]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let fontScale = Self.fontScales[level - 1]

        configuration.label
            .textual.fontScale(fontScale)
            .fontWeight(.bold)
            .padding(.top, 16)
            .padding(.bottom, 16)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
            HStack(alignment: .center) {
                Text(formatLanguageName(configuration.languageHint))
                    .font(.caption.monospaced())
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()

                CopyCodeButton(configuration: configuration)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.05))

            Divider()
                .opacity(0.5)

            // コード本体
            Overflow(isIntegratedSelection: true) {
                configuration.label
                    .textual.fontScale(0.9)
                    .monospaced()
                    .textual.lineSpacing(.fontScaled(0.39))
                    .padding()
            }
        }
#if os(visionOS)
        .background(Color.black.opacity(0.2))
#else
        .background(message.role == "user" ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
#endif
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

struct CopyCodeButton: View {
    let configuration: StructuredText.CodeBlockStyle.Configuration
    @State private var isCopied = false

    var body: some View {
        Button {
            configuration.codeBlock.copyToPasteboard()
            withAnimation {
                isCopied = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "document.on.document")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.caption2)
                Text(String(localized: "Copy"))
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
#if os(macOS)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
#endif
        }
        .buttonStyle(.plain)
        .help(String(localized: "Copy"))
        .accessibilityLabel(String(localized: "Copy"))
        .textual.excludeFromTextSelection()
    }
}

struct SimpleTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .textual.textSelection(.enabled)
    }
}


// MARK: - Document Support

// MARK: - Dedicated Style for Thinking Text

struct SimpleThinkingStyle: StructuredText.Style {
    let message: ChatMessage

    var inlineStyle: InlineStyle {
        InlineStyle()
            .strong(.fontWeight(.black))
            .emphasis(.italic)
            .link(
                .foregroundColor(.accentColor.opacity(0.8)),
                .underlineStyle(.single)
            )
            .code(
                .monospaced,
                .backgroundColor(Color.secondary.opacity(0.1))
            )
    }

    var headingStyle: some StructuredText.HeadingStyle {
        SimpleThinkingHeadingStyle()
    }

    var paragraphStyle: some StructuredText.ParagraphStyle {
        SimpleThinkingParagraphStyle()
    }

    var blockQuoteStyle: some StructuredText.BlockQuoteStyle {
        SimpleThinkingBlockQuoteStyle(message: message)
    }

    var codeBlockStyle: some StructuredText.CodeBlockStyle {
        SimpleThinkingCodeBlockStyle(message: message)
    }

    var listItemStyle: some StructuredText.ListItemStyle {
        SimpleThinkingListItemStyle()
    }

    var unorderedListMarker: some StructuredText.UnorderedListMarker {
        MocolammaThinkingUnorderedListMarker()
    }

    var orderedListMarker: some StructuredText.OrderedListMarker {
        MocolammaOrderedListMarker()
    }

    var tableStyle: some StructuredText.TableStyle {
        SimpleThinkingTableStyle(message: message)
    }

    var tableCellStyle: some StructuredText.TableCellStyle {
        SimpleThinkingTableCellStyle()
    }

    var thematicBreakStyle: some StructuredText.ThematicBreakStyle {
        StructuredText.DividerThematicBreakStyle.divider
    }

    var listSpacing: FontScaled<StructuredText.BlockSpacing> {
        .fontScaled(top: 0.5, bottom: 0.5)
    }
}

struct SimpleThinkingHeadingStyle: StructuredText.HeadingStyle {
    // シンキングテキスト用により小さいスケールを設定
    private static let fontScales: [CGFloat] = [1.5, 1.4, 1.3, 1.2, 1.1, 1.0]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let fontScale = Self.fontScales[level - 1]

        configuration.label
            .textual.fontScale(fontScale)
            .fontWeight(.bold)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

struct SimpleThinkingParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.2))
            .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.4)) // 余白を狭く
    }
}

struct SimpleThinkingBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    let message: ChatMessage

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.leading, 8)
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
            }
    }
}

struct SimpleThinkingCodeBlockStyle: StructuredText.CodeBlockStyle {
    let message: ChatMessage

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // シンキングテキスト内のコードブロックはヘッダーをより目立たなくする
            HStack(alignment: .center) {
                Text(hintText(configuration.languageHint))
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                CopyCodeButton(configuration: configuration)
                    .controlSize(.mini)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05))

            Divider().opacity(0.3)

            Overflow(isIntegratedSelection: true) {
                configuration.label
                    .textual.fontScale(0.9)
                    .monospaced()
                    .textual.lineSpacing(.fontScaled(0.2))
                    .padding(8)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.vertical, 4)
        .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.4))
    }

    private func hintText(_ hint: String?) -> String {
        guard let hint = hint?.uppercased() else {
            return String(localized: "Code")
        }
        return hint
    }
}

struct SimpleThinkingListItemStyle: StructuredText.ListItemStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(width: 16, height: 1)
                configuration.marker
            }
            configuration.block
        }
    }
}

struct SimpleThinkingTableStyle: StructuredText.TableStyle {
    let message: ChatMessage
    private static let borderWidth: CGFloat = 0.5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: Self.borderWidth, vertical: Self.borderWidth)
            .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0.8))
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(
                            Path(divider),
                            with: .style(Color.secondary.opacity(0.3))
                        )
                    }
                }
            }
            .padding(Self.borderWidth)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: Self.borderWidth)
            }
    }
}

struct SimpleThinkingTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .textual.textSelection(.enabled)
    }
}

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


