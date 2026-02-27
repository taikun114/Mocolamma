import SwiftUI
#if os(iOS)
import PhotosUI
#endif

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
    
#if os(iOS)
    @State private var photosPickerItems: [PhotosPickerItem] = []
#endif
    
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
                // プラスボタン (ビジョン非対応モデルでは無効化)
#if os(iOS)
                PhotosPicker(selection: $photosPickerItems, matching: .images) {
                    ZStack {
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!(selectedModel?.supportsVision ?? false))
                .onChange(of: photosPickerItems) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                selectedImages.append(data)
                            }
                        }
                        photosPickerItems = [] // リセット
                    }
                }
#else
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.image]
                    
                    if let window = NSApp.keyWindow {
                        panel.beginSheetModal(for: window) { response in
                            if response == .OK {
                                for url in panel.urls {
                                    if let data = try? Data(contentsOf: url) {
                                        selectedImages.append(data)
                                    }
                                }
                            }
                        }
                    } else {
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                if let data = try? Data(contentsOf: url) {
                                    selectedImages.append(data)
                                }
                            }
                        }
                    }
                }) {
                    ZStack {
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!(selectedModel?.supportsVision ?? false))
#endif
                
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
