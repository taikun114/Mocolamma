import SwiftUI

struct ContentView: View {
    @ObservedObject var executor = CommandExecutor() // CommandExecutorのインスタンス
    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    @State private var sidebarSelection: String? = "models" // サイドバーの選択状態を保持します
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    @State private var columnVisibility: NavigationSplitViewVisibility = .all // デフォルトでは全てのカラムを表示

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
                Label("Models", systemImage: "macbook.and.ipad")
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
                modelToDelete: $modelToDelete
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
        .alert("Delete Model", isPresented: $showingDeleteConfirmation, presenting: modelToDelete) { model in // 削除確認アラートのタイトル。
            Button("Delete", role: .destructive) { // アラートの削除ボタン。
                if let modelName = model?.name {
                    Task {
                        await executor.deleteModel(modelName: modelName)
                    }
                }
            }
            Button("Cancel", role: .cancel) { // アラートのキャンセルボタン。
                modelToDelete = nil
            }
        } message: { model in
            Text("Are you sure you want to delete model '\(model?.name ?? "Unknown Model")'?\nThis action cannot be undone.") // モデル削除の確認メッセージ。 // 不明なモデル。
        }
        .onAppear {
            // アプリ起動時に「Models」をデフォルトで選択状態にします
            sidebarSelection = "models"
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
                .padding(.bottom, 5) // Keep bottom padding for title
                .lineLimit(1) // 1行に制限
                .truncationMode(.tail) // はみ出た場合は省略記号

            Divider()

            Group {
                HStack {
                    Text("Model Name:") // モデル名。
                        .bold()
                    Text(model.model)
                        .lineLimit(1) // 1行に制限
                        .truncationMode(.tail) // はみ出た場合は省略記号
                }
                HStack {
                    Text("Size:") // サイズ。
                        .bold()
                    Text(model.formattedSize)
                        .lineLimit(1) // 1行に制限
                        .truncationMode(.tail) // はみ出た場合は省略記号
                }
                HStack {
                    Text("Modified At:") // 変更日。
                        .bold()
                    Text(model.formattedModifiedAt)
                        .lineLimit(1) // 1行に制限
                        .truncationMode(.tail) // はみ出た場合は省略記号
                }
                HStack {
                    Text("Digest:") // ダイジェスト。
                        .bold()
                    Text(model.digest)
                        .lineLimit(1) // 1行に制限
                        .truncationMode(.tail) // はみ出た場合は省略記号
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくすために追加

            Divider()

            Text("Details Information:") // 詳細情報（Details）。
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくすために追加


            if let details = model.details { // ここでOptionalをアンラップします
                VStack(alignment: .leading, spacing: 5) {
                    if let parentModel = details.parent_model, !parentModel.isEmpty {
                        HStack {
                            Text("Parent Model:") // 親モデル。
                                .bold()
                            Text(parentModel)
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                    if let format = details.format {
                        HStack {
                            Text("Format:") // フォーマット。
                                .bold()
                            Text(format)
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                    if let family = details.family {
                        HStack {
                            Text("Family:") // ファミリー。
                                .bold()
                            Text(family)
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                    if let families = details.families, !families.isEmpty {
                        HStack {
                            Text("Families:") // ファミリーズ。
                                .bold()
                            Text(families.joined(separator: ", "))
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                    if let parameterSize = details.parameter_size {
                        HStack {
                            Text("Parameter Size:") // パラメータサイズ。
                                .bold()
                            Text(parameterSize)
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                    if let quantizationLevel = details.quantization_level {
                        HStack {
                            Text("Quantization Level:") // 量子化レベル。
                                .bold()
                            Text(quantizationLevel)
                                .lineLimit(1) // 1行に制限
                                .truncationMode(.tail) // はみ出た場合は省略記号
                        }
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくすために追加
            } else {
                Text("No details available.") // 詳細情報はありません。
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくすために追加
            }
            
            Spacer()
        }
        .padding() // 詳細パネル全体の上下左右のパディングは保持 (これ自体が親ビューからのパディング)
    }
}

// SwiftUIのプレビュー用
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
