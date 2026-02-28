import SwiftUI
import Textual
import UniformTypeIdentifiers
import Photos
import PhotosUI

struct MessageView: View {
    @Environment(CommandExecutor.self) var executor
    @EnvironmentObject var chatSettings: ChatSettings
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
    
    // 編集用画像の状態
    @State private var editingImages: [ChatInputImage] = []
    @State private var showingAttachSheet = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var draggingItem: ChatInputImage?
    
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

    private var supportsVision: Bool {
        chatSettings.selectedModelCapabilities?.contains(where: { $0.lowercased() == "vision" }) ?? false
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
                Task {
                    for url in urls {
                        let data: Data? = if url.startAccessingSecurityScopedResource() {
                            try? Data(contentsOf: url)
                        } else {
                            try? Data(contentsOf: url)
                        }
                        
                        if let urlData = data {
                            let thumbnail = await createThumbnail(data: urlData)
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
                
                // 画像を編集用にコピー
                Task {
                    if let images = message.images {
                        editingImages = await withTaskGroup(of: (Int, ChatInputImage?).self) { group in
                            for (index, base64) in images.enumerated() {
                                group.addTask {
                                    if let data = Data(base64Encoded: base64) {
                                        return (index, await createThumbnail(data: data).map { ChatInputImage(data: data, thumbnail: $0) })
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

    private func createThumbnail(data: Data) async -> PlatformImage? {
        return await Task.detached(priority: .medium) { // .userInitiated から .medium に変更
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240
            ]
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let size = min(width, height)
            let x = (width - size) / 2
            let y = (height - size) / 2
            let cropRect = CGRect(x: x, y: y, width: size, height: size)
            
            guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                return nil
            }
            
#if os(macOS)
            return NSImage(cgImage: croppedCGImage, size: NSSize(width: 60, height: 60))
#else
            return UIImage(cgImage: croppedCGImage)
#endif
        }.value
    }
    
    private func processImagesInBackground(_ imagesData: [Data]) async -> [String] {
        return await Task.detached(priority: .medium) {
            var results: [String] = []
            for data in imagesData {
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: false
                ]
                guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { continue }
                
                // 回転情報を反映し、かつ最大解像度を2048pxに制限して処理を高速化
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, // これで回転が修正されます
                    kCGImageSourceThumbnailMaxPixelSize: 2048 // 2048pxにリサイズして負荷を軽減
                ]
                
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                    continue
                }
                
                let outputData = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(outputData, UTType.png.identifier as CFString, 1, nil) else {
                    continue
                }
                
                CGImageDestinationAddImage(destination, cgImage, nil)
                if CGImageDestinationFinalize(destination) {
                    // リサイズ済みのデータからBase64文字列を生成
                    results.append((outputData as Data).base64EncodedString())
                }
            }
            return results
        }.value
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
            
            // 編集内容を反映させるためのTaskを開始
            Task {
                // 画像の変更を反映
                if editingImages.isEmpty {
                    message.images = nil
                } else {
                    // 画像の処理が必要な場合はフラグを立てる
                    message.isProcessingImages = true
                    
                    let imagesData = editingImages.map { $0.data }
                    let base64Images = await processImagesInBackground(imagesData)
                    
                    await MainActor.run {
                        message.images = base64Images
                        message.isProcessingImages = false
                    }
                }
                
                onRetry?(message.id, message)
            }
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
        .disabled(!isModelSelected || isStreamingAny || (message.content.isEmpty && editingImages.isEmpty))
        .allowsHitTesting(!isStreamingAny)
        .transaction { $0.disablesAnimations = true }
        .id(isStreamingAny ? "on" : "off")
    }
    
    @ViewBuilder
    private var messageContentView: some View {
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
                            .onDrop(of: [.text], delegate: ImageDropDelegate(item: imageContainer, items: $editingImages, draggingItem: $draggingItem))
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

