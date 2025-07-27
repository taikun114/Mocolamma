import SwiftUI
import Foundation // Task { @MainActor in } を使用するため

// MARK: - コンテンツビュー

/// アプリのメインウィンドウを構成するSwiftUIビューです。
/// NavigationSplitViewを使用して、サイドバー（「Categories」）、中央のコンテンツエリア、およびモデル詳細（`ModelDetailsView`）の3カラムレイアウトを構築します。
/// サイドバーのビュー切り替えと、トップレベルの状態管理に特化しています。
struct ContentView: View {
    // ServerManagerのインスタンスをAppStateに保持し、ライフサイクル全体で利用可能にする
    @ObservedObject var serverManager: ServerManager
    // CommandExecutorはServerManagerに依存するため、後から初期化
    @StateObject var executor: CommandExecutor

    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    // サイドバーの選択状態を保持します (デフォルトで"server"を選択)
    @State private var sidebarSelection: String? = "server"
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    // 全てのカラムを表示する初期設定とし、Inspectorの表示を別途制御します
    @State private var columnVisibility: NavigationSplitViewVisibility = .all // デフォルトで全パネル表示

    // Inspector（プレビューパネル）の表示/非表示を制御するState変数
    @State private var showingInspector: Bool = false

    // モデル追加シートの表示/非表示を制御します
    @State private var showingAddModelsSheet = false
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
    
    // ContentViewの初期化。serverManagerを依存性として受け取り、executorを初期化します。
    // このイニシャライザはMocolammaAppから呼び出される際にServerManagerを渡すために必要です。
    init(serverManager: ServerManager) {
        self.serverManager = serverManager
        _executor = StateObject(wrappedValue: CommandExecutor(serverManager: serverManager))
    }

    var body: some View {
        // メインナビゲーションビューを呼び出し、必要なバインディングとオブジェクトを渡します
        MainNavigationView(
            sidebarSelection: $sidebarSelection,
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
        .environmentObject(executor) // CommandExecutorを環境オブジェクトとして追加
        .sheet(isPresented: $showingAddModelsSheet) { // モデル追加シートの表示は ContentView が管理
            // ServerFormView (旧 AddModelsSheet) に executor を渡す
            AddModelsSheet(showingAddSheet: $showingAddModelsSheet, executor: executor)
        }
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) { // presenting 引数を削除
            Button("Delete", role: .destructive) { // アラートの削除ボタン。
                if let model = modelToDelete { // 手動でアンラップ
                    Task {
                        await executor.deleteModel(modelName: model.name)
                    }
                }
                showingDeleteConfirmation = false // アラートを閉じる
                modelToDelete = nil // 削除対象モデルをクリア
            }
            Button("Cancel", role: .cancel) { // アラートのキャンセルボタン。
                showingDeleteConfirmation = false // アラートを閉じる
                modelToDelete = nil // 削除対象モデルをクリア
            }
        } message: {
            if let model = modelToDelete { // 手動でアンラップ
                Text(String(localized: "Are you sure you want to delete the model \"\(model.name)\"?\nThis action cannot be undone.", comment: "モデル削除の確認メッセージ。"))
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "Are you sure you want to delete the selected model?\nThis action cannot be undone.", comment: "選択したモデル削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            // アプリ起動時に「Server」をデフォルトで選択状態にします
            sidebarSelection = "server"
        }
        .onChange(of: columnVisibility) { oldVal, newVal in
            print("ContentView: カラムの表示状態が \(oldVal) から \(newVal) に変更されました")
        }
        .onChange(of: sidebarSelection) { oldSelection, newSelection in
            if newSelection == "server" {
                updateSelectedServerForInspector()
            }
        }
        .onChange(of: serverManager.selectedServerID) { oldID, newID in
            // API通信用の選択IDが変更されても、Inspectorの表示はServerViewのlistSelectionに任せる
            // ここでは何もしない
        }
        .onChange(of: selectedModel) { oldModel, newModel in
            // モデル選択が変更されたら、Inspectorの表示状態を更新
            // ここでは何もしない
        }
        .onChange(of: selectedServerForInspector) { oldServer, newServer in
            // selectedServerForInspector が変更されたら、接続状況を再チェック
            if let server = newServer {
                // serverConnectionStatus = nil // チェック中にリセット
                Task {
                    _ = await executor.checkAPIConnectivity(host: server.host)
                    await MainActor.run {
                        // serverConnectionStatus = isConnected
                    }
                }
            }
        }
    }

    // Helper function to update selectedServerForInspector and check connectivity
    private func updateSelectedServerForInspector() {
        guard let selectedID = serverManager.selectedServerID,
              let server = serverManager.servers.first(where: { $0.id == selectedID }) else {
            selectedServerForInspector = nil
            return
        }
        selectedServerForInspector = server
    }
}

// MARK: - Main Navigation View Helper
/// NavigationSplitViewとInspectorを含むメインナビゲーション構造をカプセル化するヘルパービュー
private struct MainNavigationView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool // Inspectorの表示状態をバインディングとして受け取る
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sortedModels: [OllamaModel]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) { // columnVisibilityをState変数にバインド
            // MARK: - サイドバー (左端のカラム)
            List(selection: $sidebarSelection) {
                // "Server" という項目を配置し、選択可能にします
                Label("Server", systemImage: "server.rack") // アイコンをserver.rackに
                    .tag("server")
                
                // "Models" という項目を配置し、選択可能にします
                Label("Models", systemImage: "tray.full") // アイコンをtray.fullに
                    .tag("models")
            }
            .navigationTitle("Categories") // サイドバーのタイトル
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: { // content: { から detail: { に変更し、NavigationSplitViewを2カラム構成にします
            MainContentDetailView(
                sidebarSelection: $sidebarSelection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete
            )
        }
        // MARK: - Inspector (右端のプレビューパネル)
        // Inspectorはメインコンテンツビューに追加され、独立して開閉します
        .inspector(isPresented: $showingInspector) {
            // Inspectorのコンテンツを分離したヘルパービューで管理
            InspectorContentView(
                sidebarSelection: sidebarSelection,
                selectedModel: selectedModel,
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector, // Pass new state
                serverManager: serverManager, // Pass ServerManager to InspectorContentView
                showingInspector: $showingInspector // InspectorContentViewにバインディングを渡す
            )
            // Inspectorのデフォルト幅を設定（必要に応じて調整）
            .inspectorColumnWidth(min: 250, ideal: 250, max: 400)
        }
        // Inspectorの開閉アニメーションを明示的に指定すると競合することがあるため削除
        // .animation(.default, value: showingInspector)
    }
}


// MARK: - Inspector Content Helper View
/// Inspector内部のコンテンツを表示するためのヘルパービュー
private struct InspectorContentView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let sidebarSelection: String?
    let selectedModel: OllamaModel.ID?
    let sortedModels: [OllamaModel] // ContentViewから渡されるモデルデータ
    let selectedServerForInspector: ServerInfo? // New parameter
    @ObservedObject var serverManager: ServerManager // ServerManagerを直接受け取る

    @Binding var showingInspector: Bool // Inspectorの表示状態をバインディングとして受け取る
    
    // Model Infoを保持するState
    @State private var modelInfo: [String: JSONValue]?
    @State private var isLoadingInfo: Bool = false // ローディング状態

    var body: some View {
        Group {
            if sidebarSelection == "models",
               let selectedModelID = selectedModel,
               let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                // ModelDetailsViewにmodelInfoとisLoadingInfoを渡す
                ModelDetailsView(model: model, modelInfo: modelInfo, isLoading: isLoadingInfo)
                    .id(model.id) // モデルのIDに基づいてビューの同一性を管理
            } else if sidebarSelection == "server" {
                if let server = selectedServerForInspector {
                    ServerInspectorView(server: server, connectionStatus: serverManager.serverConnectionStatuses[server.id] ?? nil)
                        .id(server.id) // Use server ID for view identity
                } else {
                    Text("Select a server to see the details.") // Fallback if no server is selected
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .id("server_selection_placeholder")
                }
            } else {
                Text("Select a model to see the details.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("model_selection_placeholder") // ユニークなIDを付与
            }
        }
        .onChange(of: selectedModel) { _, newID in
            // 選択が変更されたらリセット
            modelInfo = nil
            isLoadingInfo = true
            
            guard let newID = newID,
                  let model = sortedModels.first(where: { $0.id == newID }) else {
                isLoadingInfo = false
                return
            }
            
            Task {
                let fetchedInfo = await commandExecutor.fetchModelInfo(modelName: model.name)
                // このタスクがキャンセルされていないか、または選択が再度変更されていないか確認
                if selectedModel == newID {
                    await MainActor.run {
                        self.modelInfo = fetchedInfo
                        self.isLoadingInfo = false
                    }
                }
            }
        }
        // InspectorContentViewにツールバーを追加
        .toolbar {
            Spacer()
            Button {
                // Inspector の表示状態を切り替えます
                print("InspectorContentView: インスペクター内のボタンが押されました。現在のインスペクターの表示状態: \(showingInspector)")
                showingInspector.toggle()
                print("InspectorContentView: 新しいインスペクターの表示状態: \(showingInspector)")
            } label: {
                Image(systemName: "sidebar.right") // サイドバーの右側を示すアイコン
            }
            .help("Toggle Inspector") // ツールチップ
        }
    }
}

// MARK: - Main Content Detail Helper View
private struct MainContentDetailView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?

    var body: some View {
        Group {
            // MARK: - メインコンテンツ (右側のカラム - 旧 content カラム)
            // サイドバーの選択状態に基づいて表示するビューを切り替えます
            if sidebarSelection == "models" {
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    onTogglePreview: {
                        // Inspector の表示状態を切り替えます
                        print("ContentView: onTogglePreview を受信しました。現在のインスペクターの表示状態: \(showingInspector)")
                        showingInspector.toggle()
                        print("ContentView: 新しいインスペクターの表示状態: \(showingInspector)")
                    }
                )
            } else if sidebarSelection == "server" {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: {
                        // Inspector の表示状態を切り替えます
                        print("ContentView: サーバー用の onTogglePreview を受信しました。現在のインスペクターの表示状態: \(showingInspector)")
                        showingInspector.toggle()
                        print("ContentView: 新しいインスペクターの表示状態: \(showingInspector)")
                        
                    },
                    selectedServerForInspector: $selectedServerForInspector
                ) // ServerViewを表示
            } else {
                Text("Select a category.") // カテゴリを選択してください。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - プレビュー用

#Preview {
    // プレビュー用にダミーのServerManagerインスタンスを作成
    let previewServerManager = ServerManager()
    return ContentView(serverManager: previewServerManager)
}
