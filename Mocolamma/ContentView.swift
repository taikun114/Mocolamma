import SwiftUI

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
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly // デフォルトで詳細パネルを閉じる

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
        // NavigationSplitView を使って3カラムレイアウトを構築します
        // sidebar: 左側のナビゲーション (Categories)
        // content: 中央のコンテンツエリア (Model List or Server View)
        // detail: 右側の詳細エリア (Model Details)
        NavigationSplitView(columnVisibility: $columnVisibility) { // columnVisibilityをState変数にバインド
            // MARK: - サイドバー (左端のカラム)
            List(selection: $sidebarSelection) {
                // "Server" という項目を配置し、選択可能にします
                Label("サーバー", systemImage: "server.rack") // アイコンをserver.rackに
                    .tag("server")
                
                // "Models" という項目を配置し、選択可能にします
                Label("モデル", systemImage: "tray.full") // アイコンをtray.fullに
                    .tag("models")
            }
            .navigationTitle("カテゴリ") // サイドバーのタイトル
        } content: {
            // MARK: - コンテンツ (中央のカラム)
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
                        print("ContentView: onTogglePreview received. Current visibility: \(columnVisibility)")
                        if columnVisibility == .all {
                            columnVisibility = .detailOnly
                        } else {
                            columnVisibility = .all
                        }
                        print("ContentView: New visibility: \(columnVisibility)")
                    }
                )
            } else if sidebarSelection == "server" {
                ServerView(serverManager: serverManager, executor: executor) // ServerViewを表示
            } else {
                Text("カテゴリを選択してください。") // カテゴリを選択してください。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        } detail: {
            // MARK: - ディテール (右端のカラム: モデル詳細)
            // 選択されたモデルがある場合にのみ詳細を表示します (Modelsタブが選択されている場合のみ)
            if sidebarSelection == "models",
               let selectedModelID = selectedModel,
               let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                ModelDetailsView(model: model)
            } else {
                // モデルが選択されていない場合のプレースホルダーテキスト、またはServerタブ選択時の詳細
                Text("モデルを選択して詳細を表示するためのプレースホルダーテキスト。") // モデルを選択して詳細を表示するためのプレースホルダーテキスト。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingAddModelsSheet) { // モデル追加シートの表示は ContentView が管理
            // ServerFormView (旧 AddModelsSheet) に executor を渡す
            AddModelsSheet(showingAddSheet: $showingAddModelsSheet, executor: executor)
        }
        .alert("モデルを削除", isPresented: $showingDeleteConfirmation) { // presenting 引数を削除
            Button("削除", role: .destructive) { // アラートの削除ボタン。
                if let model = modelToDelete { // 手動でアンラップ
                    Task {
                        await executor.deleteModel(modelName: model.name)
                    }
                }
                showingDeleteConfirmation = false // アラートを閉じる
                modelToDelete = nil // 削除対象モデルをクリア
            }
            Button("キャンセル", role: .cancel) { // アラートのキャンセルボタン。
                showingDeleteConfirmation = false // アラートを閉じる
                modelToDelete = nil // 削除対象モデルをクリア
            }
        } message: {
            if let model = modelToDelete { // 手動でアンラップ
                Text(String(localized: "モデル「\(model.name)」を削除してもよろしいですか？\nこの操作は元に戻せません。", comment: "モデル削除の確認メッセージ。"))
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "選択したモデルを削除してもよろしいですか？\nこの操作は元に戻せません。", comment: "選択したモデル削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            // アプリ起動時に「Server」をデフォルトで選択状態にします
            sidebarSelection = "server"
        }
        .onChange(of: columnVisibility) { oldVal, newVal in
            print("ContentView: columnVisibility changed from \(oldVal) to \(newVal)")
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
