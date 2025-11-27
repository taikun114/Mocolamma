import SwiftUI

// MARK: - モデル追加シート

/// 新しいモデルの追加（プル）を行うためのシートビューです。ユーザーがモデル名を入力し、ダウンロードを開始するためのUIを提供します。
struct AddModelsSheet: View {
    @Binding var showingAddSheet: Bool // シートの表示/非表示を制御するバインディング
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    
    @State private var modelNameInput: String = "" // モデル名入力
    @State private var showHttpErrorAlert: Bool = false
    @State private var httpErrorMessage: String = ""
    @State private var pullErrorTriggeredSeen: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var showingOpenLinkAlert = false
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
#if os(macOS)
            Text("Add Model") // モデル追加シートのタイトル。
                .font(.title)
                .bold()
#endif
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter the name of the model you want to add") // モデル追加シートの説明。
                    .font(.headline)
                
                TextField("e.g., gemma3:4b, phi4:latest", text: $modelNameInput) // モデル追加入力フィールドのプレースホルダーテキスト。
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        // モデル追加ボタンが無効な場合は何もしない
                        if !(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling) {
                            add()
                        }
                    }
                
                Spacer() // このspacerは新旧両方の文字列に存在するため、保持する必要があります。
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find Models")
                        .font(.headline)
                    Text("If you're not sure what to enter, you can find models on the Ollama website.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
#if os(iOS) // iOSではボタンがメッセージの下に表示される
                    Button {
                        showingOpenLinkAlert = true
                    } label: {
                        Label("Open Website", systemImage: "paperclip")
                    }
                    .buttonStyle(.bordered)
#endif
                }
                
#if os(macOS)
                HStack {
                    Button {
                        showingOpenLinkAlert = true
                    } label: {
                        Label("Open Website", systemImage: "paperclip")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large) // macOS用にcontrolSizeを適用
                    
                    Spacer() // このspacerは新旧両方の文字列に存在するため、保持する必要があります。
                    Button("Cancel") { // キャンセルボタンのテキスト。
                        showingAddSheet = false
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                    
                    Button("Add") { // 追加ボタンのテキスト。
                        add()
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction) // Enterキーで実行
                    .disabled(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
                }
#endif
            }
        }
        .padding()
#if os(macOS)
        .frame(width: 400, height: 250) // シートの固定サイズ
#endif
        .onReceive(executor.$pullHttpErrorTriggered) { triggered in
            if triggered && !pullErrorTriggeredSeen {
                httpErrorMessage = executor.pullHttpErrorMessage
                showHttpErrorAlert = true
                pullErrorTriggeredSeen = true
            }
        }
        .onChange(of: showHttpErrorAlert) { _, shown in
            if shown == false {
                pullErrorTriggeredSeen = false
                executor.pullHttpErrorTriggered = false
                executor.pullHttpErrorMessage = ""
            }
        }
        .alert("Model Pull Error", isPresented: $showHttpErrorAlert) {
            Button("OK") { showHttpErrorAlert = false }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(httpErrorMessage)
        }
        .alert(String(localized: "Open Link?", comment: "外部リンクを開くアラートタイトルテキスト。"), isPresented: $showingOpenLinkAlert) {
            Button(String(localized: "Open", comment: "開くボタン。")) {
                if let url = URL(string: "https://ollama.com/library") {
                    openURL(url)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(String(localized: "Cancel", comment: "キャンセルアクションを実行するボタンテキスト。"), role: .cancel) {}
        } message: {
            Text(String(localized: "Are you sure you want to open the Ollama models page?", comment: "ユーザに、Ollamaのモデル一覧が記載されたページを開いても良いかどうかを尋ねるアラートメッセージ。"))
        }
#if os(iOS)
        .navigationTitle("Add Model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { showingAddSheet = false }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    // モデル追加ボタンが無効な場合は何もしない
                    if !(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling) {
                        add()
                    }
                }) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
                .applyGlassProminentButtonStyle(isDisabled: modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
#endif
    }
    
    private func add() {
        if !modelNameInput.isEmpty {
            let name = modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            executor.pullHttpErrorTriggered = false
            executor.pullHttpErrorMessage = ""
            executor.pullModel(modelName: name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !executor.pullHttpErrorTriggered {
                    showingAddSheet = false
                }
            }
        }
    }
}

// MARK: - プレビュー用

#Preview {
    // プレビュー用にダミーのServerManagerとCommandExecutorインスタンスを作成
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
    return AddModelsSheet(showingAddSheet: .constant(true), executor: previewCommandExecutor)
}
