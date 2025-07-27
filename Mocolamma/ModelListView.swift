import SwiftUI
import AppKit // NSPasteboard のため

// MARK: - モデルリストビュー

/// モデルのテーブル表示、ダウンロード進捗ゲージ、APIログ表示、
/// および再読み込み・モデル追加用のツールバーボタンなど、
/// モデルリストに関連するUIとロジックをカプセル化したビューです。
/// ContentViewから必要なデータとバインディングを受け取って表示を更新します。
struct ModelListView: View {
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    @Binding var selectedModel: OllamaModel.ID? // 選択されたモデルのIDをバインディングで受け取ります
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>] // ソート順をバインディングで受け取ります
    
    @Binding var showingAddSheet: Bool // モデル追加シートの表示/非表示を制御するバインディング
    @Binding var showingDeleteConfirmation: Bool // 削除確認アラートの表示/非表示を制御するバインディング
    @Binding var modelToDelete: OllamaModel? // 削除対象のモデルを保持するバインディング

    let onTogglePreview: () -> Void // プレビューパネルをトグルするためのクロージャ

    

    // 現在のソート順に基づいてモデルリストを返すComputed Property
    var sortedModels: [OllamaModel] {
        executor.models.sorted(using: sortOrder)
    }

    var body: some View {
        VStack {
            Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
                // 「番号」列: 最小30、理想50、最大無制限
                TableColumn("No.", value: \.originalIndex) { model in // テーブル列ヘッダー：番号。
                    Text("\(model.originalIndex + 1)")
                }
                .width(min: 30, ideal: 50, max: .infinity) // 番号列の幅設定を更新します

                // 「名前」列: 最小50、理想150、最大無制限
                TableColumn("Name", value: \.name) { model in // テーブル列ヘッダー：名前。
                    Text(model.name)
                }
                .width(min: 100, ideal: 200, max: .infinity) // 名前列の幅設定を更新します

                // 「サイズ」列: 最小30、理想50、最大無制限
                TableColumn("Size", value: \.comparableSize) { model in // テーブル列ヘッダー：サイズ。
                    Text(model.formattedSize) // formattedSizeを使用します
                }
                .width(min: 50, ideal: 100, max: .infinity) // サイズ列の幅設定を更新します

                // 「変更日」列: 最小50、理想80、最大無制限
                TableColumn("Modified At", value: \.comparableModifiedDate) { model in // テーブル列ヘッダー：変更日。
                    Text(model.formattedModifiedAt) // formattedModifiedAtを使用します
                }
                .width(min: 100, ideal: 150, max: .infinity) // 変更日列の幅設定を更新します
            }
            // Tableレベルでコンテキストメニューを設定
            .contextMenu(forSelectionType: OllamaModel.ID.self) { selectedIDs in
                // 選択されたモデルIDから最初のモデルを取得
                if let selectedID = selectedIDs.first,
                   let model = sortedModels.first(where: { $0.id == selectedID }) {
                    Button("Copy Model Name") { // コンテキストメニューのアクション：モデル名をコピーします。
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.name, forType: .string)
                    }
                    Button("Delete...", role: .destructive) { // コンテキストメニューのアクション：モデルを削除します。
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    }
                }
            }
            .overlay {
                if executor.apiConnectionError { // API接続エラーの場合
                    ContentUnavailableView(
                        "Connection Failed", // 接続失敗のタイトル。
                        systemImage: "network.slash",
                        description: Text("Failed to connect to the Ollama API. Please check your network connection or server settings.") // 接続失敗の説明。
                    )
                } else if executor.models.isEmpty && !executor.isRunning && !executor.isPulling { // pull中も表示されないように条件追加
                    ContentUnavailableView(
                        "No Models Available", // 利用可能なモデルなしのタイトル。
                        systemImage: "internaldrive.fill",
                        description: Text("No models are currently installed. Click '+' to add a new model.") // 利用可能なモデルなしの説明。
                    )
                } else if executor.isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(2)
                }
            }
            // プログレスバーとステータステキスト
            if executor.isPulling {
                VStack {
                    ProgressView(value: executor.pullProgress) {
                        Text(executor.pullStatus)
                    } currentValueLabel: {
                        Text(String(format: NSLocalizedString(" %.1f%% completed (%@ / %@)", comment: "ダウンロード進捗: 完了/合計。"),
                                    executor.pullProgress * 100 as CVarArg,
                                    ByteCountFormatter().string(fromByteCount: executor.pullCompleted) as CVarArg,
                                    ByteCountFormatter().string(fromByteCount: executor.pullTotal) as CVarArg))
                    }
                    .progressViewStyle(.linear)
                }
                .padding()
            }
            // コマンド実行の出力表示 (TextEditorは削除されました)
        }
        .navigationTitle("Models") // ナビゲーションタイトル: モデル。
        .toolbar { // ここで全てのToolbarItemをまとめます
            // MARK: - Reload Button (Primary Action, before Add New)
            ToolbarItem(placement: .primaryAction) { // primaryActionに配置
                Button(action: {
                    Task {
                        await executor.fetchOllamaModelsFromAPI() // モデルリストを再読み込みします
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise") // ツールバーボタン：モデルを更新します。
                }
                .disabled(executor.isRunning || executor.isPulling)
            }
            // MARK: - Add Model Button (Primary Action)
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add New", systemImage: "plus") // ツールバーボタン：新しいモデルを追加します。
                }
                .disabled(executor.isRunning || executor.isPulling)
            }
        }
        // .padding(.vertical) // 上下のパディングを削除 (これはModelListViewのものです)
        .onAppear {
            print("ModelListView Appeared. Fetching Ollama models from API.") // デバッグ用
            // ビューが表示されたときにOllama APIからモデルリストを取得します
            Task {
                await executor.fetchOllamaModelsFromAPI()
            }
        }
    }
}

// MARK: - プレビュー用

// 新しいプレビューマクロを使用し、ダミーのBindingを直接渡す
#Preview {
    // プレビュー用にダミーのServerManagerインスタンスを作成
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)

    return ModelListView(
        executor: previewCommandExecutor, // ダミーのCommandExecutorインスタンス
        selectedModel: .constant(nil), // ダミーのBinding<OllamaModel.ID?>
        sortOrder: .constant([.init(\.originalIndex, order: .forward)]), // ダミーのBinding<[KeyPathComparator<OllamaModel>]>
        showingAddSheet: .constant(false), // ダミーのBinding<Bool>
        showingDeleteConfirmation: .constant(false), // ダミーのBinding<Bool>
        modelToDelete: .constant(nil), // ダミーのBinding<OllamaModel?>
        onTogglePreview: { print("ModelListView_Previews: Dummy onTogglePreview called.") } // ダミーのクロージャ
    )
}
