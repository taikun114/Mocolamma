import SwiftUI
import Foundation // Task { @MainActor in } を使用するため
import CompactSlider
import Combine

// MARK: - コンテンツビュー

/// アプリのメインウィンドウを構成するSwiftUIビューです。
/// プラットフォームに応じて、NavigationSplitViewまたはTabViewを使用してUIを構築します。
struct ContentView: View {
    // ServerManagerのインスタンスをAppStateに保持し、ライフサイクル全体で利用可能にする
    @ObservedObject var serverManager: ServerManager
    // CommandExecutorはServerManagerに依存するため、後から初期化
    @StateObject var executor: CommandExecutor

    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    // サイドバー/タブの選択状態をAppレベルから受け取ります
    @Binding var selection: String?
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    @State private var columnVisibility: NavigationSplitViewVisibility = .all // デフォルトで全パネル表示

    // Inspector（プレビューパネル）の表示/非表示を制御するState変数を@Bindingに変更
    @Binding var showingInspector: Bool
    @StateObject private var chatSettings = ChatSettings()

    // モデル追加シートの表示/非表示を制御します
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingAddServerSheet: Bool
    @State private var showingDeleteConfirmation = false // 削除確認アラートの表示/非表示を制御します
    @State private var modelToDelete: OllamaModel? // 削除対象のモデルを保持します
    
    // ソート順を保持するState変数 (ModelListViewにバインディングとして渡します)
    @State private var sortOrder: [KeyPathComparator<OllamaModel>] = [
        .init(\.originalIndex, order: .forward)
    ]

    // 現在のソート順に基づいてモデルリストを返すComputed Property (ModelListViewに渡します)
    var sortedModels: [OllamaModel] {
        executor.models.sorted(using: sortOrder)
    }

    // MARK: - Server Inspector related states
    @State private var selectedServerForInspector: ServerInfo? // Inspectorに表示するサーバー情報
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    
    // リフレッシュトリガーを受け取る
    
    
    // ContentViewの初期化子を更新
    init(serverManager: ServerManager, selection: Binding<String?>, showingInspector: Binding<Bool>, showingAddModelsSheet: Binding<Bool>, showingAddServerSheet: Binding<Bool>, shouldClearChat: Binding<Bool>, isPulling: Binding<Bool>) {
        self.serverManager = serverManager
        _executor = StateObject(wrappedValue: CommandExecutor(serverManager: serverManager))
        self._selection = selection
        self._showingInspector = showingInspector
        self._showingAddModelsSheet = showingAddModelsSheet
        self._showingAddServerSheet = showingAddServerSheet
        self._shouldClearChat = shouldClearChat
        self._isPulling = isPulling
    }
    
    @Binding var shouldClearChat: Bool
    @Binding var isPulling: Bool

    var body: some View {
        Group {
            #if os(macOS)
            MainNavigationView(
                sidebarSelection: $selection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                columnVisibility: $columnVisibility,
                sortedModels: sortedModels
            )
            #elseif os(iOS)
            if #available(iOS 18.0, *) {
                MainTabView(
                    selection: $selection,
                    selectedModel: $selectedModel,
                    executor: executor,
                    serverManager: serverManager,
                    selectedServerForInspector: $selectedServerForInspector,
                    showingInspector: $showingInspector,
                    sortOrder: $sortOrder,
                    showingAddModelsSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    sortedModels: sortedModels
                )
            } else {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    LegacyIPhoneTabView(
                        selection: $selection,
                        selectedModel: $selectedModel,
                        executor: executor,
                        serverManager: serverManager,
                        selectedServerForInspector: $selectedServerForInspector,
                        showingInspector: $showingInspector,
                        sortOrder: $sortOrder,
                        showingAddModelsSheet: $showingAddModelsSheet,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        modelToDelete: $modelToDelete,
                        sortedModels: sortedModels
                    )
                } else {
                    MainNavigationView(
                        sidebarSelection: $selection,
                        selectedModel: $selectedModel,
                        executor: executor,
                        serverManager: serverManager,
                        selectedServerForInspector: $selectedServerForInspector,
                        showingInspector: $showingInspector,
                        sortOrder: $sortOrder,
                        showingAddModelsSheet: $showingAddModelsSheet,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        modelToDelete: $modelToDelete,
                        columnVisibility: $columnVisibility,
                        sortedModels: sortedModels
                    )
                }
            }
            #else
            MainNavigationView(
                sidebarSelection: $selection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                columnVisibility: $columnVisibility,
                sortedModels: sortedModels
            )
            #endif
        }
        .environmentObject(executor)
        .environmentObject(chatSettings)
        .sheet(isPresented: $showingAddModelsSheet) {
            NavigationStack {
                AddModelsSheet(showingAddSheet: $showingAddModelsSheet, executor: executor)
                    .environmentObject(appRefreshTrigger)
            }
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationStack {
                ServerFormView(serverManager: serverManager, executor: executor, editingServer: nil)
                    .environmentObject(appRefreshTrigger)
            }
        }
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    Task {
                        await executor.deleteModel(modelName: model.name)
                    }
                }
                showingDeleteConfirmation = false
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = false
                modelToDelete = nil
            }
            .keyboardShortcut(.defaultAction) // Added here
        } message: {
            if let model = modelToDelete { // 手動でアンラップ
                Text(String(localized: "Are you sure you want to delete the model \"\(model.name)\"?\nThis action cannot be undone.", comment: "モデル削除の確認メッセージ。"))
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "Are you sure you want to delete the selected model?\nThis action cannot be undone.", comment: "選択したモデル削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            selection = "server"
        }
        .onChange(of: selection) { oldSelection, newSelection in
            if newSelection == "server" {
                updateSelectedServerForInspector()
            }
            if newSelection == "settings" && showingInspector {
                showingInspector = false
            }
        }
        .onChange(of: serverManager.selectedServerID) { _, _ in
            // API通信用の選択IDが変更されても、Inspectorの表示はServerViewのlistSelectionに任せる
        }
        .onChange(of: selectedServerForInspector) { oldServer, newServer in
            if newServer != nil {
                if selection == "server" {
                    appRefreshTrigger.send()
                }
            }
        }
        .onChange(of: shouldClearChat) { oldValue, newValue in
            if newValue {
                // チャットクリアを実行
                executor.clearChat()
                // 状態をリセット
                shouldClearChat = false
            }
        }
        .onChange(of: executor.isPulling) { oldValue, newValue in
            isPulling = newValue
        }
        .onReceive(appRefreshTrigger.publisher) {
            Task { await performRefreshForCurrentSelection() }
        }
    }

    private func updateSelectedServerForInspector() {
        guard let selectedID = serverManager.selectedServerID,
              let server = serverManager.servers.first(where: { $0.id == selectedID }) else {
            selectedServerForInspector = nil
            return
        }
        selectedServerForInspector = server
    }
    
    private func performRefreshForCurrentSelection() async {
        guard let currentSelection = selection else { return }
        
        switch currentSelection {
        case "server":
            try? await Task.sleep(nanoseconds: 100_000_000)
            // サーバー接続状態を再チェック
            for server in serverManager.servers {
                serverManager.updateServerConnectionStatus(serverID: server.id, status: .checking)
                Task {
                    let connectionStatus = await executor.checkAPIConnectivity(host: server.host)
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: server.id, status: connectionStatus)
                    }
                }
            }
            
        case "models":
            try? await Task.sleep(nanoseconds: 100_000_000)
            // モデルリストを再取得
            Task {
                executor.isPullingErrorHold = false
                executor.pullHasError = false
                executor.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
                executor.clearModelInfoCache()
                let previousSelection = selectedModel
                let selectedServerID = serverManager.selectedServerID
                selectedModel = nil
                
                if let sid = selectedServerID {
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: sid, status: .checking)
                    }
                }
                
                await executor.fetchOllamaModelsFromAPI()

                if let sid = selectedServerID, let host = serverManager.servers.first(where: { $0.id == sid })?.host {
                    let status = await executor.checkAPIConnectivity(host: host)
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: sid, status: status)
                    }
                }

                await MainActor.run {
                    serverManager.inspectorRefreshToken = UUID()
                    NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
                }
                if let prev = previousSelection, executor.models.contains(where: { $0.id == prev }) {
                    selectedModel = prev
                }
            }
            
        case "chat":
            // チャットではモデルリストを再取得
            Task {
                executor.clearModelInfoCache()
                await executor.fetchOllamaModelsFromAPI()
            }
            
        default:
            break
        }
    }
}

// MARK: - プレビュー用
#Preview {
    let previewServerManager = ServerManager()
    ContentView(serverManager: previewServerManager, selection: .constant("server"), showingInspector: .constant(false), showingAddModelsSheet: .constant(false), showingAddServerSheet: .constant(false), shouldClearChat: .constant(false), isPulling: .constant(false))
        .environmentObject(RefreshTrigger())
}
