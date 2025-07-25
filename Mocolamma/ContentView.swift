import SwiftUI

// ContentViewは、アプリのメインウィンドウを構成するSwiftUIビューです。
// NavigationSplitViewを使用して、サイドバー、モデルリスト、およびモデル詳細の3カラムレイアウトを構築します。
// アプリ全体の状態（選択されたモデル、シート、アラートなど）を管理し、下位ビューにバインディングとして渡します。
// このファイルは、サイドバーのビュー切り替えと、トップレベルの状態管理に特化しています。
struct ContentView: View {
    @ObservedObject var executor = CommandExecutor() // CommandExecutorのインスタンス
    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    // サイドバーの選択状態を保持します。デフォルトを"server"に変更します。
    @State private var sidebarSelection: String? = "server"
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly // デフォルトで詳細パネルを閉じる

    @State private var showingAddSheet = false // モデル追加シートの表示/非表示を制御します
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

    var body: some View {
        // NavigationSplitView を使って3カラムレイアウトを構築します
        // sidebar: 左側のナビゲーション (Categories)
        // content: 中央のコンテンツエリア (Model List / Server View)
        // detail: 右側の詳細エリア (Model Details)
        NavigationSplitView(columnVisibility: $columnVisibility) { // columnVisibilityをState変数にバインド
            // MARK: - サイドバー (左端のカラム)
            List(selection: $sidebarSelection) {
                // "Server" という項目を"Models"の上に配置し、選択可能にします
                Label("Server", systemImage: "cloud.fill") // アイコンをcloud.fillに変更
                    .tag("server")

                // "Models" という項目だけを配置し、選択可能にします
                Label("Models", systemImage: "tray.full") // アイコンをtray.fullに変更
                    .tag("models")
            }
            .navigationTitle("Categories") // サイドバーのタイトル
        } content: {
            // MARK: - コンテンツ (中央のカラム)
            // sidebarSelectionに基づいて表示するビューを切り替えます
            switch sidebarSelection {
            case "server":
                ServerView() // 新しいServerViewを表示
            case "models":
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    onTogglePreview: { // クロージャを渡す
                        print("ContentView: onTogglePreview received. Current visibility: \(columnVisibility)")
                        if columnVisibility == .all {
                            columnVisibility = .detailOnly
                        } else {
                            columnVisibility = .all
                        }
                        print("ContentView: New visibility: \(columnVisibility)")
                    }
                )
            default:
                // デフォルトのビュー、またはエラーメッセージ
                Text("Select a category from the sidebar.") // サイドバーからカテゴリを選択してください。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        } detail: {
            // MARK: - ディテール (右端のカラム: モデル詳細)
            // 選択されたモデルがある場合にのみ詳細を表示します
            if let selectedModelID = selectedModel,
               let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                ModelDetailsView(model: model)
            } else {
                // モデルが選択されていない場合のプレースホルダーテキスト
                Text("Select a model to view details.") // モデルを選択して詳細を表示するためのプレースホルダーテキスト。
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingAddSheet) { // シートの表示は ContentView が管理
            AddModelsSheet(showingAddSheet: $showingAddSheet, executor: executor)
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
                Text(String(localized: "Are you sure you want to delete model '\(model.name)'?\nThis action cannot be undone.")) // モデル削除の確認メッセージ。
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "Are you sure you want to delete the selected model?\nThis action cannot be undone."))
            }
        }
        .onAppear {
            // アプリ起動時にデフォルトで「Server」を選択状態にします
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

// 新しいプレビューマクロを使用
#Preview {
    ContentView()
}
