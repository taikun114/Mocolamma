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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.containerHeight) private var containerHeight
    
    // 編集用画像の状態
    @State private var editingImages: [ChatInputImage] = []
    @State private var showingAttachSheet = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var draggingItem: ChatInputImage?
    @State private var isDraggingOver = false
    
    // 保存関連の状態
    @State private var isSaveOptionsPresented: Bool = false
    @State private var isFileExporterPresented: Bool = false
    @State private var imageDocument: ImageDocument?
    @State private var isThinkingExpanded: Bool = false
    @State private var isStreamingSettled: Bool = true
    
    private var isDownloadSuccessful: Bool {
        message.isDownloadSuccessful
    }
    
    private var isCopied: Bool {
        message.isCopied
    }

    private var supportsVision: Bool {
        chatSettings.selectedModelCapabilities?.contains(where: { $0.lowercased() == "vision" }) ?? false
    }
    
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        return formatter
    }()
    
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
                    if isEditing && isDraggingOver && supportsVision {
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
                                Text("Drop here to add images")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .onDrop(of: [.fileURL, .image], delegate: AreaImageDropDelegate(items: $editingImages, isDraggingOver: $isDraggingOver, isEnabled: supportsVision, onURLsDropped: { urls in
                    if isEditing && supportsVision {
                        addImages(from: urls)
                    }
                }, onDataDropped: { data in
                    if isEditing && supportsVision {
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
            .onChange(of: message.isStreaming) { _, newValue in
                if !newValue {
                    // ストリーミング終了後、マークダウンの再描画などが安定するまで少し待ってから機能を有効化
                    isStreamingSettled = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isStreamingSettled = true
                    }
                }
            }
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
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addImages(from: urls)
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
    
    private func addImages(from urls: [URL]) {
        Task {
            for url in urls {
                let data: Data? = if url.startAccessingSecurityScopedResource() {
                    try? Data(contentsOf: url)
                } else {
                    try? Data(contentsOf: url)
                }
                
                if let urlData = data, PlatformImage(data: urlData) != nil {
                    let thumbnail = await ChatInputImage.createThumbnail(from: urlData)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingImages.append(ChatInputImage(data: urlData, thumbnail: thumbnail))
                        }
                    }
                    url.stopAccessingSecurityScopedResource()
                    // 少しだけ待機して、左から順に現れるようにする
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
    }

    private func addImages(from data: [Data]) {
        Task {
            for urlData in data {
                if PlatformImage(data: urlData) != nil {
                    let thumbnail = await ChatInputImage.createThumbnail(from: urlData)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingImages.append(ChatInputImage(data: urlData, thumbnail: thumbnail))
                        }
                    }
                    // 少しだけ待機して、左から順に現れるようにする
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
            if !editingImages.isEmpty && !supportsVision {
                showingVisionWarningAlert = true
                return
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
        .disabled(!isModelSelected || isStreamingAny || (message.content.isEmpty && (editingImages.isEmpty || !supportsVision)))
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
    }
    
    private func performDone(skipImages: Bool = false) {
        isEditing = false
        
        // 編集内容を反映させるためのTaskを開始
        Task {
            // 画像の変更を反映
            if editingImages.isEmpty || skipImages {
                message.images = nil
            } else {
                // 画像の処理が必要な場合はフラグを立てる
                message.isProcessingImages = true
                
                let imagesData = editingImages.map { $0.data }
                let base64Images = await ChatInputImage.processImages(imagesData)
                
                await MainActor.run {
                    message.images = base64Images
                    message.isProcessingImages = false
                }
            }
            
            onRetry?(message.id, message)
        }
    }
    
    @ViewBuilder
    private var messageContentView: some View {
        @Bindable var message = message
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
            if message.isProcessingImages {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing images...")
                        .font(.caption)
                        .foregroundColor(message.role == "user" ? .white.opacity(0.8) : .secondary)
                }
                .padding(.vertical, 4)
            } else if isEditing && message.role == "user" && (supportsVision || !editingImages.isEmpty) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(editingImages) { imageContainer in
                            ZStack(alignment: .topLeading) {
                                if let image = imageContainer.thumbnail {
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
                            .onDrop(of: [.text], delegate: ImageDropDelegate(item: imageContainer, items: $editingImages, draggingItem: $draggingItem, isDraggingOver: .constant(false)))
                        }
                        
                        // 画像追加タイル (ビジョン対応モデルが選択されている場合のみ表示)
                        if supportsVision {
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
                            .confirmationDialog(
                                Text("Attach Images"),
                                isPresented: $showingAttachSheet,
                                titleVisibility: .visible
                            ) {
                                Button(String(localized: "Photo Library...")) {
                                    showingPhotoPicker = true
                                }
                                Button(String(localized: "Choose Files...")) {
                                    showingFilePicker = true
                                }
                                Button(String(localized: "Cancel"), role: .cancel) { }
                            } message: {
                                Text("Please select the location of the images you want to attach.")
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 90)
                .scrollClipDisabled()
            } else if let images = message.images, !images.isEmpty {
                // 画像が少ないときはバブルを画像幅に合わせ、多いときはスクロールさせる
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { base64 in
                            if let data = Data(base64Encoded: base64),
                               let image = PlatformImage(data: data) {
                                Image(platformImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            onPreviewImage?(image)
                                        }
                                    }
                            }
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(images, id: \.self) { base64 in
                                if let data = Data(base64Encoded: base64),
                                   let image = PlatformImage(data: data) {
                                    Image(platformImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
#if os(visionOS)
                                        .hoverEffect()
#endif
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                onPreviewImage?(image)
                                            }
                                        }
                                }
                            }
                        }
                    }
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
                        .textualSelection(enabled: isStreamingSettled && !message.isStreaming && !isStreamingAny) // 全体ストリーミング中も無効化
                        .textual.syntaxHighlightingEnabled(isStreamingSettled && !message.isStreaming && !isStreamingAny)
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
                            .textualSelection(enabled: isStreamingSettled && !(message.isStreaming && !message.isThinkingCompleted) && !isStreamingAny)
                            .textual.syntaxHighlightingEnabled(isStreamingSettled && !(message.isStreaming && !message.isThinkingCompleted) && !isStreamingAny)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .compositingGroup() // 描画を最適化（.drawingGroupはメッセージがレンダリングできなくなるため使用しない）
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
                    .textualSelection(enabled: isStreamingSettled && !message.isStreaming)
                    .textual.syntaxHighlightingEnabled(isStreamingSettled && !message.isStreaming)
                    .textual.overflowMode(.scroll)
                    .compositingGroup() // 描画を最適化（.drawingGroupはメッセージがレンダリングできなくなるため使用しない）
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
            .textual.blockSpacing(.fontScaled(top: 1, bottom: 1))
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


