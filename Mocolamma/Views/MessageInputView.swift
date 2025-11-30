import SwiftUI

struct MessageInputView: View {
    @FocusState private var isInputFocused: Bool
    @Binding var inputText: String
    @Binding var isStreaming: Bool
    @Binding var showingInspector: Bool
    var selectedModel: OllamaModel?
    var sendMessage: () -> Void
    var stopMessage: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .bottom) {
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
                TextField("Type your message...", text: $inputText, axis: .vertical)
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
                .disabled(isStreaming ? false : (inputText.isEmpty || selectedModel == nil))
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
                .disabled(isStreaming ? false : (inputText.isEmpty || selectedModel == nil))
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
                .disabled(isStreaming ? false : (inputText.isEmpty || selectedModel == nil))
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
                .disabled(isStreaming ? false : (inputText.isEmpty || selectedModel == nil))
            }
#endif
            
        }
        .background(Color.clear)
    }
}
