import SwiftUI

// MARK: - サーバービュー

/// アプリケーションのメインサイドバーからアクセスされるサーバーコンテンツのUIを定義するSwiftUIビューです。
/// サーバーのリストを表示し、新しいサーバーの追加、既存サーバーの編集を管理します。
struct ServerView: View {
    @ObservedObject var serverManager: ServerManager // ServerManagerのインスタンスを受け取ります
    @ObservedObject var executor: CommandExecutor // 接続確認と編集のためにCommandExecutorのインスタンスを受け取ります

    @State private var showingAddServerSheet = false // サーバー追加シートの表示/非表示を制御します
    @State private var serverToEdit: ServerInfo? // 編集対象のサーバーを保持します (sheet(item:)にIdentifiableとして渡す)
    @State private var showingDeleteConfirmationServer = false // サーバー削除確認アラートの表示/非表示を制御します
    @State private var serverToDelete: ServerInfo? // 削除対象のサーバーを保持します
    @State private var listSelection: ServerInfo.ID? // リストのハイライト表示のみを制御するID

    let onTogglePreview: () -> Void // プレビューパネルをトグルするためのクロージャ

    @Binding var selectedServerForInspector: ServerInfo? // Inspectorに表示する選択されたサーバー情報

    

    var body: some View {
        VStack {
            // ListにlistSelectionバインディングを追加し、クリックで選択（ハイライト）されるようにします。
            List(selection: $listSelection) {
                ForEach(serverManager.servers) { server in
                    ServerRowContent(
                        server: server,
                        serverManager: serverManager,
                        listSelection: $listSelection,
                        serverToEdit: $serverToEdit,
                        showingDeleteConfirmationServer: $showingDeleteConfirmationServer,
                        serverToDelete: $serverToDelete,
                        isSelected: server.id == serverManager.selectedServerID
                    )
                }
                .onMove(perform: serverManager.moveServer)
            }
            // List全体にprimaryActionを設定し、ダブルクリック/Enterキーで選択を実行します。
            // contextMenu(forSelectionType:menu:primaryAction:)のprimaryAction引数を使用します。
            
            .navigationTitle("Servers") // ナビゲーションタイトル
            .overlay {
                if serverManager.servers.isEmpty {
                    ContentUnavailableView(
                        "No Servers Available",
                        systemImage: "server.fill",
                        description: Text("No servers are currently configured. Click '+' to add a new server.")
                    )
                }
            }
        }
        .toolbar {
            // MARK: - サーバー追加ボタン
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingAddServerSheet = true
                }) {
                    Label("Add Server", systemImage: "plus")
                }
            }
            // MARK: - Toggle Preview Panel Button
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onTogglePreview() // クロージャを呼び出す
                    print("ServerView: Toggle Preview button tapped.")
                } label: {
                    Label("Toggle Preview", systemImage: "sidebar.trailing") // ツールバーボタン：プレビューを切り替えます。
                }
            }
        }
        .sheet(isPresented: $showingAddServerSheet) {
            // 新しいサーバー追加シートを表示
            ServerFormView(serverManager: serverManager, executor: executor, editingServer: nil)
        }
        // serverToEditがnilでなくなったときにシートを表示するためにsheet(item:)を使用
        .sheet(item: $serverToEdit) { server in
            ServerFormView(serverManager: serverManager, executor: executor, editingServer: server)
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmationServer) { // presenting 引数を削除
            Button("Delete", role: .destructive) {
                if let server = serverToDelete {
                    serverManager.deleteServer(server)
                }
                showingDeleteConfirmationServer = false
                serverToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmationServer = false
                serverToDelete = nil
            }
        } message: {
            if let server = serverToDelete {
                Text(String(localized: "Are you sure you want to delete the server \"\(server.name)\"\nThis action cannot be undone.", comment: "サーバー削除の確認メッセージ。"))
            } else {
                Text(String(localized: "Are you sure you want to delete the selected server?\nThis action cannot be undone.", comment: "選択したサーバー削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            // ビューが表示されたとき、選択されているサーバーがなければ、最初のサーバーを選択（存在する場合）
            if serverManager.selectedServerID == nil && !serverManager.servers.isEmpty {
                serverManager.selectedServerID = serverManager.servers.first?.id
            }
            // APIとの通信用選択IDに基づいて、リストのハイライトも設定
            listSelection = serverManager.selectedServerID
            
            // 全てのサーバーの接続状態をチェック
            checkAllServerConnectivity()
        }
        .onChange(of: serverManager.servers) { oldServers, newServers in
            handleServerListChange(oldServers: oldServers, newServers: newServers)
        }
        .onChange(of: listSelection) { oldID, newID in
            handleListSelectionChange(oldID: oldID, newID: newID)
        }
    }

    private func checkAllServerConnectivity() {
        for server in serverManager.servers {
            serverManager.updateServerConnectionStatus(serverID: server.id, status: nil) // チェック中に設定
            Task {
                let isConnected = await executor.checkAPIConnectivity(host: server.host)
                await MainActor.run {
                    serverManager.updateServerConnectionStatus(serverID: server.id, status: isConnected)
                }
            }
        }
    }

    private func handleServerListChange(oldServers: [ServerInfo], newServers: [ServerInfo]) {
        // サーバーリストが変更された場合、選択中のサーバーがまだ存在するか確認し、なければクリアまたは再選択
        if let selectedID = serverManager.selectedServerID, !newServers.contains(where: { $0.id == selectedID }) {
            serverManager.selectedServerID = newServers.first?.id
        }
        // リストのハイライトも更新
        listSelection = serverManager.selectedServerID
        
        // サーバーリストが変更されたら、全てのサーバーの接続状態を再チェック
        checkAllServerConnectivity()
    }

    private func handleListSelectionChange(oldID: ServerInfo.ID?, newID: ServerInfo.ID?) {
        // リストのハイライトが変更されたら、Inspectorに表示するサーバーも更新
        if let newID = newID {
            selectedServerForInspector = serverManager.servers.first(where: { $0.id == newID })
        } else {
            selectedServerForInspector = nil
        }
    }
}

private struct ServerRowContent: View {
    let server: ServerInfo
    @ObservedObject var serverManager: ServerManager
    @Binding var listSelection: ServerInfo.ID?
    @Binding var serverToEdit: ServerInfo?
    @Binding var showingDeleteConfirmationServer: Bool
    @Binding var serverToDelete: ServerInfo?
    let isSelected: Bool

    var body: some View {
        ServerRowView(
            server: server,
            isSelected: isSelected,
            connectionStatus: serverManager.serverConnectionStatuses[server.id] ?? nil
        )
        .contextMenu { // 右クリックコンテキストメニュー
            // コンテキストメニューの先頭に「Select」オプションを追加
            Button("Select") {
                serverManager.selectedServerID = server.id
                listSelection = server.id // リストのハイライトも連動させる
            }

            Button("Edit...") { // 編集ボタン
                serverToEdit = server // シート表示のためにアイテムを設定
            }
            Button("Delete...", role: .destructive) { // 削除ボタン
                serverToDelete = server
                showingDeleteConfirmationServer = true
            }
        }
    }
}

// MARK: - プレビュー

#Preview {
    // プレビュー用にダミーのServerManagerとCommandExecutorインスタンスを作成
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)

    // プレビューの初期状態を設定
    previewServerManager.servers = [
        ServerInfo(name: "Local", host: "localhost:11434"),
        ServerInfo(name: "Remote Server 1", host: "192.168.1.50:11434"),
        ServerInfo(name: "Remote Server 2", host: "api.example.com:11434")
    ]
    previewServerManager.selectedServerID = previewServerManager.servers.first?.id

    return ServerView(
        serverManager: previewServerManager,
        executor: previewCommandExecutor,
        onTogglePreview: { print("ServerView_Preview: Dummy onTogglePreview called.") },
        selectedServerForInspector: .constant(previewServerManager.servers.first)
    )
}
