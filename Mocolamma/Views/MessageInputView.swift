import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 画像プレビュー
            if !selectedImages.isEmpty {
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
                            .onDrop(of: [.text], delegate: ImageDropDelegate(item: imageContainer, items: $selectedImages, draggingItem: $draggingItem))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 76)
                .scrollClipDisabled()
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
                                    selectedImages.append(ChatInputImage(data: urlData, thumbnail: thumbnail))
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
    }

    private func createThumbnail(data: Data) async -> PlatformImage? {
        return await Task.detached(priority: .medium) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240 // クロップ用に少し余裕を持ってデコード
            ]
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            
            // 中央を正方形にクロップ
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
}

// MARK: - ImageDropDelegate

struct ImageDropDelegate: DropDelegate {
    let item: ChatInputImage
    @Binding var items: [ChatInputImage]
    @Binding var draggingItem: ChatInputImage?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem != item,
              let from = items.firstIndex(where: { $0.id == draggingItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if items[to].id != draggingItem.id {
            withAnimation {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
}

// MARK: - PhotoLibraryPicker

#if os(iOS)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [ChatInputImage]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0 // 複数選択
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        if let data = data {
                            Task {
                                let thumbnail = await self.parent.createThumbnail(data: data)
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        self.parent.selectedImages.append(ChatInputImage(data: data, thumbnail: thumbnail))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func createThumbnail(data: Data) async -> PlatformImage? {
        return await Task.detached(priority: .medium) {
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
            
            return UIImage(cgImage: croppedCGImage)
        }.value
    }
}
#else
struct PhotoLibraryPicker: NSViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [ChatInputImage]

    func makeNSViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0 // 複数選択
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateNSViewController(_ nsViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            for result in results {
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        if let data = data {
                            Task {
                                let thumbnail = await self.parent.createThumbnail(data: data)
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        self.parent.selectedImages.append(ChatInputImage(data: data, thumbnail: thumbnail))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func createThumbnail(data: Data) async -> PlatformImage? {
        return await Task.detached(priority: .medium) {
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
            
            return NSImage(cgImage: croppedCGImage, size: NSSize(width: 60, height: 60))
        }.value
    }
}
#endif
