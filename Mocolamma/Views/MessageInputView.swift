import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Environment(CommandExecutor.self) var executor
    @FocusState private var isInputFocused: Bool
    @Binding var inputText: String
    @Binding var selectedImages: [ChatInputImage]
    @Binding var isStreaming: Bool
    @Binding var showingInspector: Bool
    var placeholder: String = "Type your message..."
    var selectedModel: OllamaModel?
    var sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil
    
    // 添付オプション関連の状態
    @State private var showingAttachSheet = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var draggingItem: ChatInputImage?
    @State private var isDraggingOver = false
    
    var body: some View {
        @Bindable var executor = executor
        VStack(alignment: .leading, spacing: 8) {
            // 画像プレビュー
            if !selectedImages.isEmpty || (executor.isDraggingFile && selectedModel?.supportsVision == true) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(selectedImages) { imageContainer in
                            ZStack(alignment: .topLeading) {
                                if let image = imageContainer.thumbnail {
#if os(iOS)
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
#else
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
#endif
                                }
                                
                                Button(action: {
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
                            .onDrop(of: [.text], delegate: ImageDropDelegate(item: imageContainer, items: $selectedImages, draggingItem: $draggingItem, isDraggingOver: .constant(false)))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 76)
                .scrollClipDisabled()
                .overlay {
                    if executor.isDraggingFile && selectedModel?.supportsVision == true {
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
                                Text("Drop here to add images")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                    }
                }
            }
            
            HStack(alignment: .bottom) {
                // プラスボタン (アクションシートを表示)
                Button(action: {
                    showingAttachSheet = true
                }) {
                    ZStack {
#if os(iOS)
                        if #available(iOS 26, *) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(8)
                                .glassEffect(.regular.interactive())
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
                                .glassEffect(.regular.interactive())
                        } else {
                            Image(systemName: "plus")
                                .font(.title2)
                                .padding(7)
                                .background(Circle().fill(.thinMaterial))
                        }
#endif
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!(selectedModel?.supportsVision ?? false))
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
                
                ZStack(alignment: .leading) {
#if os(iOS)
                    if #available(iOS 26, *) {
                        Color.clear
                            .glassEffect(in: .rect(cornerRadius: 16.0))
                    } else {
                        VisualEffectView(material: .systemThinMaterial)
                            .cornerRadius(16)
                    }
#else
                    if #available(macOS 26, *) {
                        Color.clear
                            .glassEffect(in: .rect(cornerRadius: 16.0))
                    } else {
                        VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                            .cornerRadius(16)
                    }
#endif
                    TextField(LocalizedStringKey(placeholder), text: $inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .textFieldStyle(.plain)
                        .disabled(selectedModel == nil)
                        .onChange(of: selectedModel) { _, model in
                            if model != nil && !showingInspector { isInputFocused = true }
                        }
                        .lineLimit(1...10)
                        .fixedSize(horizontal: false, vertical: true) // 高さをコンテンツに合わせる
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.clear) // TextFieldの背景を透明にする
                    
                        .cornerRadius(16) // 角を丸くする
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
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
                .fixedSize(horizontal: false, vertical: true)
                
#if os(iOS)
                if #available(iOS 26, *) {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .glassEffect(.regular.tint(.accentColor).interactive())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming ? false : (inputText.isEmpty && selectedImages.isEmpty || selectedModel == nil))
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
                    .disabled(isStreaming ? false : (inputText.isEmpty && selectedImages.isEmpty || selectedModel == nil))
                }
#else
                if #available(macOS 26, *) {
                    Button(action: isStreaming ? (stopMessage ?? {}) : sendMessage) {
                        ZStack {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(7)
                                .glassEffect(.regular.tint(.accentColor).interactive())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming ? false : (inputText.isEmpty && selectedImages.isEmpty || selectedModel == nil))
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
                    .disabled(isStreaming ? false : (inputText.isEmpty && selectedImages.isEmpty || selectedModel == nil))
                }
#endif
            }
        }
        .background(Color.clear)
        .onDrop(of: [.fileURL, .image], delegate: AreaImageDropDelegate(items: $selectedImages, isDraggingOver: $isDraggingOver, executor: executor, isEnabled: selectedModel?.supportsVision ?? false, onURLsDropped: { urls in
            addImages(from: urls)
        }, onDataDropped: { data in
            addImages(from: data)
        }))
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
    }
    
    private func addImages(from urls: [URL]) {
        Task {
            for url in urls {
                let data: Data? = if url.startAccessingSecurityScopedResource() {
                    try? Data(contentsOf: url)
                } else {
                    try? Data(contentsOf: url)
                }
                
                if let urlData = data {
                    let thumbnail = await ChatInputImage.createThumbnail(from: urlData)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedImages.append(ChatInputImage(data: urlData, thumbnail: thumbnail))
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
                let thumbnail = await ChatInputImage.createThumbnail(from: urlData)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedImages.append(ChatInputImage(data: urlData, thumbnail: thumbnail))
                    }
                }
                // 少しだけ待機して、左から順に現れるようにする
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
}
