import SwiftUI

// MARK: - サーバーフォームビュー

/// 新しいOllamaサーバーの追加、または既存サーバーの編集を行うためのシートビューです。
/// サーバー名とホストURLの入力欄を提供し、保存時に接続確認を行います。
struct ServerFormView: View {
    @Environment(\.dismiss) var dismiss // シートを閉じるための環境変数
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @ObservedObject var serverManager: ServerManager // ServerManagerのインスタンスを受け取ります
    @ObservedObject var executor: CommandExecutor // 接続確認のためにCommandExecutorのインスタンスを受け取ります
    
    @State private var serverNameInput: String
    @State private var serverHostInput: String
    @State private var showingConnectionErrorAlert = false // 接続エラーアラートの表示/非表示
    @State private var isVerifying = false // 接続確認中の状態を追跡
    @FocusState private var isNameFieldFocused: Bool
    var editingServer: ServerInfo?
    
    /// 初期化。追加の場合はnil、編集の場合は既存のServerInfoを渡します。
    /// - Parameters:
    ///   - serverManager: ServerManagerのインスタンス。
    ///   - executor: CommandExecutorのインスタンス（接続確認用）。
    ///   - editingServer: 編集中のServerInfoオブジェクト。新しいサーバー追加の場合はnil。
    init(serverManager: ServerManager, executor: CommandExecutor, editingServer: ServerInfo?) {
        self.serverManager = serverManager
        self.executor = executor
        self.editingServer = editingServer
        
        // 編集モードの場合、既存のサーバー情報で入力フィールドを初期化
        _serverNameInput = State(initialValue: editingServer?.name ?? "")
        _serverHostInput = State(initialValue: editingServer?.host ?? "")
    }
    
    // 保存/更新ボタンを無効化するための計算プロパティ
    private var isSaveButtonDisabled: Bool {
        serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
#if os(macOS)
            Text(editingServer == nil ? "Add Server" : "Edit Server")
                .font(.title)
                .bold()
#endif
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Name")
                    .font(.headline)
                TextField("e.g., Ollama Server", text: $serverNameInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        save()
                    }
                
                Text("Host")
                    .font(.headline)
                TextField("e.g., localhost:11434 or 192.168.1.50:11434", text: $serverHostInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        save()
                    }
                
#if os(iOS)
                if isVerifying {
                    HStack {
                        ProgressView()
                        Text("Connecting...")
                        Spacer()
                    }
                    .padding(.top)
                }
#endif
                
                Spacer()
            }
            
#if os(macOS)
            HStack(alignment: .center) {
                if isVerifying {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Connecting...")
                }
                Spacer()
                Button("Cancel") { // キャンセルボタン
                    dismiss() // シートを閉じる
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button(editingServer == nil ? "Save" : "Update") { // 保存/更新ボタン
                    save()
                }
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .controlSize(.large)
                .disabled(isSaveButtonDisabled)
            }
#endif
        }
        .padding()
#if os(macOS)
        .frame(width: 350, height: 250) // シートの固定サイズ
#endif
        .alert(LocalizedStringKey("ConnectionError.title"), isPresented: $showingConnectionErrorAlert) {
            Button("OK") { }
                .keyboardShortcut(.defaultAction)
            Button(editingServer == nil ? "Add Anyway" : "Update Anyway") {
                let processedHost = processHostInput(serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines))
                if let server = editingServer {
                    // 編集モード: サーバーを更新
                    serverManager.updateServer(
                        serverInfo: ServerInfo(id: server.id, name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                    )
                } else {
                    // 追加モード: 新しいサーバーを追加
                    serverManager.addServer(name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                }
                appRefreshTrigger.send() // リフレッシュをトリガー
                dismiss() // シートを閉じる
            }
        } message: {
            Text(LocalizedStringKey(executor.specificConnectionErrorMessage ?? "ConnectionError.message"))
        }
#if os(iOS)
        .navigationTitle(editingServer == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    save()
                }) {
                    Image(systemName: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveButtonDisabled)
                .applyGlassProminentButtonStyle(isDisabled: isSaveButtonDisabled)
            }
        }
        .onAppear {
            isNameFieldFocused = true
        }
#endif
    }
    
    /// 保存/更新処理
    private func save() {
        guard !isSaveButtonDisabled else { return } // 保存ボタンが無効の場合は何もしない
        
        Task {
            let trimmedHost = serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // ホスト名が「demo-mode」の場合はデモサーバーとして扱う
            if trimmedHost.lowercased() == "demo-mode" {
                isVerifying = false // 接続確認は行わない
                
                // デモモードの場合、接続確認は行わず、デモサーバーを直接追加
                if let server = editingServer {
                    // 編集モード: サーバーを更新
                    serverManager.updateServer(
                        serverInfo: ServerInfo(id: server.id, name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: "demo-mode", isDemo: true)
                    )
                } else {
                    // 追加モード: 新しいデモサーバーを追加
                    serverManager.addServer(name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: "demo-mode", isDemo: true)
                }
                appRefreshTrigger.send() // リフレッシュをトリガー
                dismiss() // シートを閉じる
            } else {
                isVerifying = true // 接続確認を開始
                let processedHost = processHostInput(trimmedHost)
                
                // ホスト名が「demo-mode」でない場合は通常の接続確認を行う
                let connectionStatus = await executor.checkAPIConnectivity(host: processedHost)
                isVerifying = false // 接続確認を終了
                
                if case .connected = connectionStatus {
                    if let server = editingServer {
                        // 編集モード: サーバーを更新
                        serverManager.updateServer(
                            serverInfo: ServerInfo(id: server.id, name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                        )
                    } else {
                        // 追加モード: 新しいサーバーを追加
                        serverManager.addServer(name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                    }
                    appRefreshTrigger.send() // リフレッシュをトリガー
                    dismiss() // シートを閉じる
                } else {
                    // 接続失敗: アラートを表示
                    showingConnectionErrorAlert = true
                }
            }
        }
    }
    
    private func processHostInput(_ host: String) -> String {
        let lowercasedHost = host.lowercased()
        
        // ホスト名が「demo-mode」の場合は特別処理
        if lowercasedHost == "demo-mode" {
            return "demo-mode"
        }
        
        // 最後のコロンを探す
        if let lastColonIndex = lowercasedHost.lastIndex(of: ":") {
            let afterColon = lowercasedHost[lowercasedHost.index(after: lastColonIndex)...]
            // 最後のコロンの後の文字がすべて数字かどうかを確認
            if !afterColon.isEmpty && afterColon.allSatisfy({ $0.isNumber }) {
                // ポート番号が存在する場合はそのまま返す
                return lowercasedHost
            }
        }
        
        // コロンがない、またはコロンの後にポート番号がない場合は、デフォルトポートを追加する
        return lowercasedHost + ":11434"
    }
}

// MARK: - プレビュー

#Preview {
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
    // 追加モードのプレビュー
    return ServerFormView(serverManager: previewServerManager, executor: previewCommandExecutor, editingServer: nil)
}

#Preview("Edit Mode") {
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    let dummyServer = ServerInfo(name: "Test Server", host: "192.168.1.100:11434")
    
    // 編集モードのプレビュー
    return ServerFormView(serverManager: previewServerManager, executor: previewCommandExecutor, editingServer: dummyServer)
}
