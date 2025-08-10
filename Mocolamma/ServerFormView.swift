import SwiftUI

// MARK: - サーバーフォームビュー

/// 新しいOllamaサーバーの追加、または既存サーバーの編集を行うためのシートビューです。
/// サーバー名とホストURLの入力欄を提供し、保存時に接続確認を行います。
struct ServerFormView: View {
    @Environment(\.dismiss) var dismiss // シートを閉じるための環境変数
    @ObservedObject var serverManager: ServerManager // ServerManagerのインスタンスを受け取ります
    @ObservedObject var executor: CommandExecutor // 接続確認のためにCommandExecutorのインスタンスを受け取ります

    @State private var serverNameInput: String
    @State private var serverHostInput: String
    @State private var showingConnectionErrorAlert = false // 接続エラーアラートの表示/非表示
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editingServer == nil ? "Add Server" : "Edit Server") // シートのタイトル
                .font(.title)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                Text("Name") // 名前ラベル
                    .font(.headline)
                TextField("e.g., Ollama Server", text: $serverNameInput) // 名前入力フィールド
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Text("Host") // ホストラベル
                    .font(.headline)
                TextField("e.g., localhost:11434 or 192.168.1.50:11434", text: $serverHostInput) // ホスト入力フィールド
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { // キャンセルボタン
                    dismiss() // シートを閉じる
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル

                Button(editingServer == nil ? "Save" : "Update") { // 保存/更新ボタン
                    Task {
                        let processedHost = processHostInput(serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        // ホストに接続できることを確認
                        let isConnected = await executor.checkAPIConnectivity(host: processedHost)

                        if isConnected {
                            if let server = editingServer {
                                // 編集モード: サーバーを更新
                                serverManager.updateServer(
                                    serverInfo: ServerInfo(id: server.id, name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                                )
                            } else {
                                // 追加モード: 新しいサーバーを追加
                                serverManager.addServer(name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost)
                            }
                            dismiss() // シートを閉じる
                        } else {
                            // 接続失敗: アラートを表示
                            showingConnectionErrorAlert = true
                        }
                    }
                }
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .controlSize(.large)
                .disabled(serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 250) // シートの固定サイズ
        .alert(LocalizedStringKey("ConnectionError.title"), isPresented: $showingConnectionErrorAlert) { // 接続エラーアラート
            Button("OK") { }
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
                dismiss() // シートを閉じる
            }
        } message: {
            Text(LocalizedStringKey("ConnectionError.message"))
        }
    }
private func processHostInput(_ host: String) -> String {
        if host.contains(":") {
            return host
        } else {
            return host + ":11434"
        }
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
