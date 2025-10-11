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
    // 編集中のサーバー情報 (追加の場合はnil)
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
            Text(editingServer == nil ? "Add Server" : "Edit Server") // シートのタイトル
                .font(.title)
                .bold()
            #endif

            VStack(alignment: .leading, spacing: 10) {
                Text("Name") // 名前ラベル
                    .font(.headline)
                TextField("e.g., Ollama Server", text: $serverNameInput) // 名前入力フィールド
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        // サーバー追加ボタンが無効な場合は何もしない
                        if !isSaveButtonDisabled {
                            save()
                        }
                    }

                Text("Host") // ホストラベル
                    .font(.headline)
                TextField("e.g., localhost:11434 or 192.168.1.50:11434", text: $serverHostInput) // ホスト入力フィールド
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        // サーバー追加ボタンが無効な場合は何もしない
                        if !isSaveButtonDisabled {
                            save()
                        }
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
        .alert(LocalizedStringKey("ConnectionError.title"), isPresented: $showingConnectionErrorAlert) { // 接続エラーアラート
            Button("OK") { }
            .keyboardShortcut(.defaultAction) // Added here
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
                    // サーバー追加ボタンが無効な場合は何もしない
                    if !isSaveButtonDisabled {
                        save()
                    }
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
        Task {
            isVerifying = true // 接続確認を開始
            let processedHost = processHostInput(serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines))
            // ホストに接続できることを確認
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

    private func processHostInput(_ host: String) -> String {
        let lowercasedHost = host.lowercased()

        // Find the last colon
        if let lastColonIndex = lowercasedHost.lastIndex(of: ":") {
            let afterColon = lowercasedHost[lowercasedHost.index(after: lastColonIndex)...]
            // Check if characters after the last colon are all digits
            if !afterColon.isEmpty && afterColon.allSatisfy({ $0.isNumber }) {
                // A port number exists, return as is
                return lowercasedHost
            }
        }

        // No colon, or colon not followed by a port number, append default port
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
