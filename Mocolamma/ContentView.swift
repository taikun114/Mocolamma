import SwiftUI

struct ContentView: View {
    @ObservedObject var executor = CommandExecutor() // CommandExecutorのインスタンス
    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    @State private var sidebarSelection: String? = "models" // サイドバーの選択状態を保持します
    
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
        // content: 中央のコンテンツエリア (Model List)
        // detail: 右側の詳細エリア (Model Details)
        NavigationSplitView(columnVisibility: $columnVisibility) { // columnVisibilityをState変数にバインド
            // MARK: - サイドバー (左端のカラム)
            List(selection: $sidebarSelection) {
                // "Models" という項目だけを配置し、選択可能にします
                Label("Models", systemImage: "tray.full") // アイコンをtray.fullに変更
                    .tag("models")
            }
            .navigationTitle("Categories") // サイドバーのタイトル
        } content: {
            // MARK: - コンテンツ (中央のカラム: モデルリストとログ)
            // ModelListView をここに配置し、必要なバインディングを渡します
            ModelListView(
                executor: executor,
                selectedModel: $selectedModel,
                sortOrder: $sortOrder,
                showingAddSheet: $showingAddSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete, // ここを修正: Bindingとして渡す
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
            // アプリ起動時に「Models」をデフォルトで選択状態にします
            sidebarSelection = "models"
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

// MARK: - モデル追加シート

struct AddModelsSheet: View {
    @Binding var showingAddSheet: Bool
    @ObservedObject var executor: CommandExecutor
    @State private var modelNameInput: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Model") // モデル追加シートのタイトル。
                .font(.title)
                .bold()

            Text("Enter the name of the model you want to add.") // モデル追加シートの説明。
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("e.g., gemma3:4b, phi4:latest", text: $modelNameInput) // モデル追加入力フィールドのプレースホルダーテキスト。
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            HStack {
                Button("Cancel") { // キャンセルボタンのテキスト。
                    showingAddSheet = false
                }
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button("Add") { // 追加ボタンのテキスト。
                    if !modelNameInput.isEmpty {
                        executor.pullModel(modelName: modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        showingAddSheet = false // シートを閉じます
                    }
                }
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .disabled(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 250) // シートの最小サイズ
    }
}

// MARK: - モデル詳細ビュー

struct ModelDetailsView: View { // 構造体名 ModelDetailsView はそのまま
    let model: OllamaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // タイトルをモデルの名前に変更
            Text(model.name) // モデル詳細のタイトルをモデル名に変更。
                .font(.title2)
                .bold()
                .padding(.bottom, 5)

            Divider()

            Group {
                VStack(alignment: .leading) {
                    Text("Model Name:") // モデル名。
                    Text(model.model)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Size:") // サイズ。
                    Text(model.formattedSize)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Modified At:") // 変更日。
                    Text(model.formattedModifiedAt)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Digest:") // ダイジェスト。
                    Text(model.digest)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.body) // ラベルのフォントサイズは維持
            .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす

            Divider()

            Text("Details Information:") // 詳細情報（Details）。
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす

            if let details = model.details { // ここでOptionalをアンラップします
                VStack(alignment: .leading, spacing: 10) { // 各VStackの間にスペースを追加
                    if let parentModel = details.parent_model, !parentModel.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Parent Model:") // 親モデル。
                            Text(parentModel)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let format = details.format {
                        VStack(alignment: .leading) {
                            Text("Format:") // フォーマット。
                            Text(format)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let family = details.family {
                        VStack(alignment: .leading) {
                            Text("Family:") // ファミリー。
                            Text(family)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let families = details.families, !families.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Families:") // ファミリーズ。
                            Text(families.joined(separator: ", "))
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let parameterSize = details.parameter_size {
                        VStack(alignment: .leading) {
                            Text("Parameter Size:") // パラメータサイズ。
                            Text(parameterSize)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let quantizationLevel = details.quantization_level {
                        VStack(alignment: .leading) {
                            Text("Quantization Level:") // 量子化レベル。
                            Text(quantizationLevel)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .font(.subheadline) // ラベルのフォントサイズは維持
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす
            } else {
                Text("No details available.") // 詳細情報はありません。
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす
            }
            
            Spacer()
        }
        .padding() // 全体のパディング
    }
}

// SwiftUIのプレビュー用
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
