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

    @State private var showingAddModelsSheet = false // モデル追加シートの表示/非表示を制御します
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
    
    // ContentViewの初期化。serverManagerを依存性として受け取り、executorを初期化します。
    // このイニシャライザはMocolammaAppから呼び出される際にServerManagerを渡すために必要です。
    init(serverManager: ServerManager) {
        self.serverManager = serverManager
        _executor = StateObject(wrappedValue: CommandExecutor(serverManager: serverManager))
    }

    var body: some View {
        // NavigationSplitView を使って2カラムレイアウトを構築します (サイドバーとメインコンテンツ)
        // ディテールはInspectorとして別に管理します
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
        } detail: { // content: { から detail: { に変更し、NavigationSplitViewを2カラム構成にします
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
                        // レイアウトの競合を避けるため、メインアクターで非同期に切り替えをディスパッチします
                        Task { @MainActor in
                            self.showingInspector.toggle()
                            print("ContentView: 新しいインスペクターの表示状態: \(self.showingInspector)")
                        }
                    }
                )
            } else if sidebarSelection == "server" {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: {
                        // Inspector の表示状態を切り替えます
                        print("ContentView: サーバー用の onTogglePreview を受信しました。現在のインスペクターの表示状態: \(showingInspector)")
                        // レイアウトの競合を避けるため、メインアクターで非同期に切り替えをディスパッチします
                        Task { @MainActor in
                            self.showingInspector.toggle()
                            print("ContentView: 新しいインスペクターの表示状態: \(self.showingInspector)")
                        }
                    }
                ) // ServerViewを表示
            } else {
                Text("Select a category.") // カテゴリを選択してください。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        // MARK: - Inspector (右端のプレビューパネル)
        // Inspectorはメインコンテンツビューに追加され、独立して開閉します
        .inspector(isPresented: $showingInspector) {
            // Inspectorのコンテンツを分離したヘルパービューで管理
            InspectorContentView(
                sidebarSelection: sidebarSelection,
                selectedModel: selectedModel,
                sortedModels: sortedModels
            )
            // Inspectorのデフォルト幅を設定（必要に応じて調整）
            .inspectorColumnWidth(ideal: 300)
        }
        // Inspectorの開閉アニメーションを明示的に指定すると競合することがあるため削除
        // .animation(.default, value: showingInspector)
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
    }
}

// MARK: - Inspector Content Helper View
/// Inspector内部のコンテンツを表示するためのヘルパービュー
private struct InspectorContentView: View {
    let sidebarSelection: String?
    let selectedModel: OllamaModel.ID?
    let sortedModels: [OllamaModel] // ContentViewから渡されるモデルデータ

    var body: some View {
        Group {
            if sidebarSelection == "models",
               let selectedModelID = selectedModel,
               let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                ModelDetailsView(model: model)
                    .id(model.id) // モデルのIDに基づいてビューの同一性を管理
            } else if sidebarSelection == "server" {
                Text("Server information will be displayed here.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("server_info_placeholder") // ユニークなIDを付与
            } else {
                Text("Select a model to see the details.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("model_selection_placeholder") // ユニークなIDを付与
            }
        }
    }
}

// カスタムカラー定義 (必要であれば別のファイルに移動します)
extension Color {
    static let textEditorBackground = Color(NSColor.textBackgroundColor)
}

// MARK: - プレビュー用

#Preview {
    // プレビュー用にダミーのServerManagerインスタンスを作成
    let previewServerManager = ServerManager()
    return ContentView(serverManager: previewServerManager)
}
