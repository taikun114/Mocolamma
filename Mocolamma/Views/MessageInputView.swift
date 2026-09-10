import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Environment(CommandExecutor.self) var executor
    @FocusState private var isInputFocused: Bool
    @Binding var inputText: String
    @Binding var selectedImages: [ChatInputImage]
    @Binding var selectedAttachments: [ChatInputAttachment]
    @Binding var isStreaming: Bool
    @Binding var showingInspector: Bool
    var placeholder: String = "Type your message..."
    var selectedModel: OllamaModel?
    var sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil
    
    init(
        inputText: Binding<String>,
        selectedImages: Binding<[ChatInputImage]>,
        selectedAttachments: Binding<[ChatInputAttachment]> = .constant([]),
        isStreaming: Binding<Bool>,
        showingInspector: Binding<Bool>,
        placeholder: String = "Type your message...",
        selectedModel: OllamaModel?,
        sendMessage: @escaping () -> Void,
        stopMessage: (() -> Void)? = nil
    ) {
        self._inputText = inputText
        self._selectedImages = selectedImages
        self._selectedAttachments = selectedAttachments
        self._isStreaming = isStreaming
        self._showingInspector = showingInspector
        self.placeholder = placeholder
        self.selectedModel = selectedModel
        self.sendMessage = sendMessage
        self.stopMessage = stopMessage
    }
    
    // 添付オプション関連の状態
    @State private var showingAttachSheet = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var draggingItem: ChatInputImage?
    @State private var draggingAttachment: ChatInputAttachment?
    @State private var isDraggingOver = false
    @State private var showingUnsupportedFileAlert = false
    @State private var unsupportedFileAlertTitle = "This file cannot be attached"
    
    /// 添付（ファイルまたは画像）が可能かどうかを判定します
    private var canAttach: Bool {
        guard let model = selectedModel else { return false }
        return model.supportsCompletion || model.supportsVision
    }
    
    /// 送信ボタンを無効化するかどうかを判定します
    private var isSendDisabled: Bool {
        if isStreaming { return false }
        guard let model = selectedModel else { return true }
        
        let hasText = !inputText.isEmpty
        let hasAttachments = !selectedAttachments.isEmpty
        let hasImages = !selectedImages.isEmpty
        
        if model.supportsVision {
            // ビジョン対応モデル: テキスト、添付ファイル、画像のいずれかがあれば送信可能
            return !hasText && !hasAttachments && !hasImages
        } else {
            // ビジョン非対応モデル: テキストまたは添付ファイルのいずれかが必要（画像のみは不可）
            return !hasText && !hasAttachments
        }
    }
    
    var body: some View {
        @Bindable var executor = executor
        VStack(alignment: .leading, spacing: 8) {
                // 添付ファイル＆画像プレビュー
                let hasPreviewItems = !selectedImages.isEmpty || !selectedAttachments.isEmpty
                if hasPreviewItems || executor.isDraggingFile {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(selectedImages) { imageContainer in
                                ZStack(alignment: .topLeading) {
                                    if imageContainer.isLoading {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(width: 60, height: 60)
                                            .overlay {
                                                ProgressView()
                                                    .controlSize(.small)
                                            }
                                    } else if let image = imageContainer.thumbnail {
                                        Image(platformImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .contentShape(Rectangle())
#if os(visionOS)
                                            .hoverEffect()
#endif
                                            .onTapGesture {
                                                if let fullImage = PlatformImage(data: imageContainer.data) {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        executor.previewImage = fullImage
                                                    }
                                                }
                                            }
                                    }
                                    
                                    Button(action: {
                                        imageContainer.loadTask?.cancel()
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedImages.removeAll(where: { $0.id == imageContainer.id })
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -8, y: -8)
                                }
                                .padding(.top, 8)
                                .padding(.leading, 8)
                                .transition(.scale(0.5).combined(with: .opacity).combined(with: .blurReplace))
                                .onDrag {
                                    self.draggingItem = imageContainer
                                    return NSItemProvider(object: imageContainer.id.uuidString as NSString)
                                }
                                .onDrop(of: [.fileURL, .image, .text], delegate: ImageDropDelegate(
                                    item: imageContainer,
                                    items: $selectedImages,
                                    draggingItem: $draggingItem,
                                    isDraggingOver: $isDraggingOver,
                                    executor: executor,
                                    onURLsDropped: { handleDroppedURLs($0) },
                                    onDataDropped: { addImages(from: $0) }
                                ))
                            }
                            
                            ForEach(selectedAttachments) { attachment in
                                ZStack(alignment: .topLeading) {
                                    FileAttachmentTileView(attachment: attachment, size: 60)
                                    
                                    Button(action: {
                                        attachment.loadTask?.cancel()
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedAttachments.removeAll(where: { $0.id == attachment.id })
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -8, y: -8)
                                }
                                .padding(.top, 8)
                                .padding(.leading, 8)
                                .transition(.scale(0.5).combined(with: .opacity).combined(with: .blurReplace))
                                .onDrag {
                                    self.draggingAttachment = attachment
                                    return NSItemProvider(object: attachment.id.uuidString as NSString)
                                }
                                .onDrop(of: [.fileURL, .image, .text], delegate: AttachmentDropDelegate(
                                    item: attachment,
                                    items: $selectedAttachments,
                                    draggingItem: $draggingAttachment,
                                    isDraggingOver: $isDraggingOver,
                                    executor: executor,
                                    onURLsDropped: { handleDroppedURLs($0) },
                                    onDataDropped: { addImages(from: $0) }
                                ))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 76)
                    .scrollClipDisabled()
                    .onDrop(of: [.fileURL, .image, .text], delegate: AreaImageDropDelegate(
                        items: $selectedImages,
                        isDraggingOver: $isDraggingOver,
                        executor: executor,
                        isEnabled: canAttach,
                        onURLsDropped: { handleDroppedURLs($0) },
                        onDataDropped: { addImages(from: $0) }
                    ))
                    .overlay {
                        if executor.isDraggingFile {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                    )
                                    .background(isDraggingOver ? Color.accentColor.opacity(0.1) : Color.clear)
                                
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                    Text("Drop here to add files")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.accentColor)
                            }
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                        }
                    }
                }
                
                HStack(alignment: .bottom) {
                // プラスボタン (アクションシートを表示)
                Button(action: {
                    showingAttachSheet = true
                }) {
#if os(visionOS)
                    Image(systemName: "plus")
                        .font(.title2)
                        .padding(8)
#else
                    ZStack {
#if !os(macOS)
                        if #available(iOS 26, visionOS 26.0, *) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(8)
#if !os(visionOS)
                                .glassEffect(.regular.interactive())
#endif
                        } else {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(8)
                                .background(Circle().fill(.thinMaterial))
                        }
#else
                        if #available(macOS 26, *) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(7)
#if !os(visionOS)
                                .glassEffect(.regular.interactive())
#endif
                        } else {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(7)
                                .background(Circle().fill(.thinMaterial))
                        }
#endif
                    }
                    .contentShape(Rectangle())
#endif
                }
#if os(visionOS)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
#else
                .buttonStyle(.plain)
#endif
                .disabled(!canAttach)
                .attachFileConfirmationDialog(
                    isPresented: $showingAttachSheet,
                    showingFilePicker: $showingFilePicker,
                    showingPhotoPicker: $showingPhotoPicker,
                    supportsCompletion: selectedModel?.supportsCompletion == true,
                    supportsVision: selectedModel?.supportsVision == true
                )
                
                ZStack(alignment: .leading) {
#if !os(macOS)
                    if #available(iOS 26, visionOS 26.0, *) {
                        Color.clear
#if !os(visionOS)
                            .glassEffect(in: .rect(cornerRadius: 24.0))
#endif
                    } else {
                        VisualEffectView(material: .systemThinMaterial)
                            .cornerRadius(24)
                    }
#else
                    if #available(macOS 26, *) {
                        Color.clear
#if !os(visionOS)
                            .glassEffect(in: .rect(cornerRadius: 24.0))
#endif
                    } else {
                        VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                            .cornerRadius(24)
                    }
#endif
                    TextField(LocalizedStringKey(placeholder), text: $inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .textFieldStyle(.plain)
#if os(visionOS)
                        .hoverEffectDisabled()
#endif
                        .disabled(selectedModel == nil)
                        .onChange(of: selectedModel) { _, model in
                            if model != nil { isInputFocused = true }
                        }
                        .lineLimit(1...10)
                        .fixedSize(horizontal: false, vertical: true) // 高さをコンテンツに合わせる
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .onSubmit { // macOSでの変換確定とEnterキー押下の処理を分離
#if os(macOS)
                            if !isStreaming {
                                sendMessage()
                            }
#else
                            if !isStreaming {
                                sendMessage()
                            }
#endif
                        }
                        .onKeyPress(KeyEquivalent.return) { // Enterキー押下時の処理（Shift+Enterでの改行用）
#if os(macOS)
                            if NSEvent.modifierFlags.contains(.shift) {
                                inputText += "\n"
                                return .handled
                            } else if isStreaming {
                                return .handled
                            } else {
                                // onSubmitに任せる
                                return .ignored
                            }
#else
                            if isStreaming {
                                return .handled
                            } else {
                                sendMessage()
                                return .handled
                            }
#endif
                        }
                }
                .contentShape(.rect(cornerRadius: 24))
                .onTapGesture {
                    if selectedModel != nil {
                        isInputFocused = true
                    }
                }
#if os(visionOS)
                .hoverEffect()
                .background(.regularMaterial, in: .rect(cornerRadius: 24))
#endif
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .fixedSize(horizontal: false, vertical: true)
                
#if !os(macOS)
                if #available(iOS 26, visionOS 26.0, *) {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
#if os(visionOS)
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.title2)
                            .padding(8)
#else
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .glassEffect(.regular.tint(.accentColor).interactive())
                        }
                        .contentShape(Rectangle())
#endif
                    }
#if os(visionOS)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.accentColor)
                    .foregroundStyle(.white)
#else
                    .buttonStyle(.plain)
#endif
                    .disabled(isSendDisabled)
                } else {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendDisabled)
                }
#else
                if #available(macOS 26, *) {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
#if os(visionOS)
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.title2)
                            .padding(8)
#else
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(7)
                                .glassEffect(.regular.tint(.accentColor).interactive())
                        }
                        .contentShape(Rectangle())
#endif
                    }
#if os(visionOS)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.accentColor)
                    .foregroundStyle(.white)
#else
                    .buttonStyle(.plain)
#endif
                    .disabled(isSendDisabled)
                } else {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(7)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendDisabled)
                }
#endif
            }
        }
        .opacity(selectedModel == nil ? 0.5 : 1.0)
        .allowsHitTesting(selectedModel != nil)
        .background(Color.clear)
        .onDrop(of: [.fileURL, .image, .text], delegate: AreaImageDropDelegate(
            items: $selectedImages,
            isDraggingOver: $isDraggingOver,
            executor: executor,
            isEnabled: canAttach,
            onURLsDropped: { urls in
                handleDroppedURLs(urls)
            },
            onDataDropped: { data in
                addImages(from: data)
            }
        ))
        // 各種ピッカーのモディファイア
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoLibraryPicker(isPresented: $showingPhotoPicker, selectedImages: $selectedImages)
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
        .alert(
            Text(LocalizedStringKey(unsupportedFileAlertTitle)),
            isPresented: $showingUnsupportedFileAlert
        ) {
            Button("OK") { }
        } message: {
            Text("Only text, PDF, or image files (vision-capable models only) can be attached.")
        }
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
                            selectedAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = selectedAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedAttachments.removeAll(where: { $0.id == placeholderId })
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
                            selectedImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = selectedImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                } else if let textContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .japaneseEUC) ?? String(data: data, encoding: .utf16) {
                    let attachment = ChatInputAttachment(name: url.lastPathComponent, content: textContent)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAttachments.append(attachment)
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
                            selectedAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = selectedAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedAttachments.removeAll(where: { $0.id == placeholderId })
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
                            selectedImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = selectedImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    successCount += 1
                } else if let textContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .japaneseEUC) ?? String(data: data, encoding: .utf16) {
                    let attachment = ChatInputAttachment(name: url.lastPathComponent, content: textContent)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAttachments.append(attachment)
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
                            selectedAttachments.append(ChatInputAttachment(id: placeholderId, name: pdfFileName, content: "", isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let attachment = await task.value {
                            await MainActor.run {
                                if let index = selectedAttachments.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedAttachments[index] = attachment
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedAttachments.removeAll(where: { $0.id == placeholderId })
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
                            selectedImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                        }
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = selectedImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
    }
}
