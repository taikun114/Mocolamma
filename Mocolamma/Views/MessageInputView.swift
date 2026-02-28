import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @FocusState private var isInputFocused: Bool
    @Binding var inputText: String
    @Binding var selectedImages: [Data]
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 画像プレビュー
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<selectedImages.count, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                if let image = loadImage(data: selectedImages[index]) {
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
                                    selectedImages.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 8, y: -8)
                            }
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 76)
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
                for url in urls {
                    // セキュリティスコープのアクセス開始
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url) {
                            selectedImages.append(data)
                        }
                    } else {
                        // スコープアクセスなしでも読み込みを試みる（ローカルファイル等）
                        if let data = try? Data(contentsOf: url) {
                            selectedImages.append(data)
                        }
                    }
                }
            case .failure(let error):
                print("Error picking files: \(error.localizedDescription)")
            }
        }
    }

#if os(iOS)
    private func loadImage(data: Data) -> UIImage? {
        UIImage(data: data)
    }
#else
    private func loadImage(data: Data) -> NSImage? {
        NSImage(data: data)
    }
#endif
}

// MARK: - PhotoLibraryPicker

#if os(iOS)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [Data]

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
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(data)
                            }
                        }
                    }
                }
            }
        }
    }
}
#else
struct PhotoLibraryPicker: NSViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [Data]

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
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(data)
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
