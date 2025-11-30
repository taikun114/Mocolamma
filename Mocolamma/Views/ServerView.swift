import SwiftUI

// MARK: - サーバービュー

/// アプリケーションのメインサイドバーからアクセスされるサーバーコンテンツのUIを定義するSwiftUIビューです。
/// サーバーのリストを表示し、新しいサーバーの追加、既存サーバーの編集を管理します。
struct ServerView: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var executor: CommandExecutor
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    
    @State private var showingAddServerSheet = false
    @State private var serverToEdit: ServerInfo?
    @State private var showingDeleteConfirmationServer = false
    @State private var serverToDelete: ServerInfo?
    @State private var listSelection: ServerInfo.ID?
    
    let onTogglePreview: () -> Void
    
    @Binding var selectedServerForInspector: ServerInfo?
    
    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }
    
    @ToolbarContentBuilder
    private var serverToolbarContent: some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
#endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                showingAddServerSheet = true
            }) {
                Label("Add Server", systemImage: "plus")
            }
        }
        
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onTogglePreview() }) {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
        }
#endif
    }
    
    var body: some View {
        ServerListViewContent(
            serverManager: serverManager,
            executor: executor,
            listSelection: $listSelection,
            serverToEdit: $serverToEdit,
            showingDeleteConfirmationServer: $showingDeleteConfirmationServer,
            serverToDelete: $serverToDelete,
            appRefreshTrigger: appRefreshTrigger
        )
        .navigationTitle("Servers")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .overlay {
            if serverManager.servers.isEmpty {
                ContentUnavailableView(
                    "No Servers Available",
                    systemImage: "server.rack",
                    description: Text("No servers are currently configured. Click or tap '+' to add a new server.")
                )
            }
        }
        .toolbar {
            serverToolbarContent
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationStack {
                ServerFormView(serverManager: serverManager, executor: executor, editingServer: nil)
                    .environmentObject(appRefreshTrigger)
            }
        }
        .sheet(item: $serverToEdit) { server in
            NavigationStack {
                ServerFormView(serverManager: serverManager, executor: executor, editingServer: server)
                    .environmentObject(appRefreshTrigger)
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmationServer) {
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
            .keyboardShortcut(.defaultAction)
        } message: {
            if let server = serverToDelete {
                Text(String(localized: "Are you sure you want to delete the server \"\(server.name)\"?\nThis action cannot be undone.", comment: "サーバー削除の確認メッセージ。"))
            } else {
                Text(String(localized: "Are you sure you want to delete the selected server?\nThis action cannot be undone.", comment: "選択したサーバー削除の確認メッセージ（フォールバック）。"))
            }
        }
        .task {
            if serverManager.selectedServerID == nil && !serverManager.servers.isEmpty {
                serverManager.selectedServerID = serverManager.servers.first?.id
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                appRefreshTrigger.send()
            }
        }
        .onChange(of: serverManager.servers) { oldServers, newServers in
            handleServerListChange(oldServers: oldServers, newServers: newServers)
        }
        .onChange(of: listSelection) { oldID, newID in
            handleListSelectionChange(oldID: oldID, newID: newID)
        }
        .onChange(of: serverManager.selectedServerID) { _, newID in
            listSelection = newID
        }
    }
    
    private func checkAllServerConnectivity() {
        for server in serverManager.servers {
            serverManager.updateServerConnectionStatus(serverID: server.id, status: .checking)
            Task {
                let connectionStatus = await executor.checkAPIConnectivity(host: server.host)
                await MainActor.run {
                    serverManager.updateServerConnectionStatus(serverID: server.id, status: connectionStatus)
                }
            }
        }
    }
    
    private func handleServerListChange(oldServers: [ServerInfo], newServers: [ServerInfo]) {
        if let selectedID = serverManager.selectedServerID, !newServers.contains(where: { $0.id == selectedID }) {
            serverManager.selectedServerID = newServers.first?.id
        }
        listSelection = serverManager.selectedServerID
        appRefreshTrigger.send()
    }
    
    private func handleListSelectionChange(oldID: ServerInfo.ID?, newID: ServerInfo.ID?) {
        if let newID = newID {
            selectedServerForInspector = serverManager.servers.first(where: { $0.id == newID })
        } else {
            selectedServerForInspector = nil
        }
    }
}

private struct ServerListViewContent: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var executor: CommandExecutor
    @Binding var listSelection: ServerInfo.ID?
    @Binding var serverToEdit: ServerInfo?
    @Binding var showingDeleteConfirmationServer: Bool
    @Binding var serverToDelete: ServerInfo?
    @ObservedObject var appRefreshTrigger: RefreshTrigger
    
    var body: some View {
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
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        serverManager.selectedServerID = server.id
                    } label: {
                        Label("Select", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        serverToDelete = server
                        showingDeleteConfirmationServer = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        serverToEdit = server
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
#if os(iOS)
                .onTapGesture {
                    listSelection = server.id
                }
#endif
            }
            .onMove(perform: serverManager.moveServer)
        }
        .contextMenu(forSelectionType: ServerInfo.ID.self, menu: { _ in }) { selectedIDs in
#if os(macOS)
            if let selectedID = selectedIDs.first {
                serverManager.selectedServerID = selectedID
            }
#endif
        }
#if os(iOS)
        .refreshable {
            appRefreshTrigger.send()
        }
#endif
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
#if os(iOS)
        .contentShape(Rectangle())
        
#endif
        .contextMenu { // 右クリックコンテキストメニュー
            Button("Select", systemImage: "checkmark.circle") {
                serverManager.selectedServerID = server.id
            }
            
            
            Button("Edit...", systemImage: "pencil") { // 編集ボタン
                serverToEdit = server
            }
            
            
            Button("Delete...", systemImage: "trash", role: .destructive) { // 削除ボタン
                serverToDelete = server
                showingDeleteConfirmationServer = true
            }
            
        }
    }
}

// MARK: - プレビュー

#Preview {
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
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
    .environmentObject(RefreshTrigger())
}
