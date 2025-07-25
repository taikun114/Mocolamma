// ContentView.swift
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
        .alert("Delete Model", isPresented: $showingDeleteConfirmation, presenting: modelToDelete) { model in // 削除確認アラートは ContentView が管理
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
            Text(String(format: "Are you sure you want to delete model '%@'?\nThis action cannot be undone.", model?.name ?? "Unknown Model")) // モデル削除の確認メッセージ。 // 不明なモデル。
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

// MARK: - モデル追加シート (変更なし)

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

            TextField("e.g., llama3, mistral", text: $modelNameInput) // モデル追加入力フィールドのプレースホルダーテキスト。
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

// MARK: - モデル詳細ビュー (変更なし)

struct ModelDetailsView: View { // 構造体名 ModelDetailsView はそのまま
    let model: OllamaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Details") // モデル詳細のタイトル。
                .font(.title2)
                .bold()
                .padding(.bottom, 5)

            Divider()

            Group {
                HStack {
                    Text("Name:") // 名前。
                        .bold()
                    Text(model.name)
                }
                HStack {
                    Text("Model Name:") // モデル名。
                        .bold()
                    Text(model.model)
                }
                HStack {
                    Text("Size:") // サイズ。
                        .bold()
                    Text(model.formattedSize)
                }
                HStack {
                    Text("Modified At:") // 変更日。
                        .bold()
                    Text(model.formattedModifiedAt)
                }
                HStack {
                    Text("Digest:") // ダイジェスト。
                        .bold()
                    Text(model.digest)
                }
            }
            .font(.body)
            .padding(.horizontal)

            Divider()

            Text("Details Information:") // 詳細情報（Details）。
                .font(.headline)
                .padding(.horizontal)

            if let details = model.details { // ここでOptionalをアンラップします
                VStack(alignment: .leading, spacing: 5) {
                    if let parentModel = details.parent_model, !parentModel.isEmpty {
                        Text("Parent Model: \(parentModel)") // 親モデル。
                    }
                    if let format = details.format {
                        Text("Format: \(format)") // フォーマット。
                    }
                    if let family = details.family {
                        Text("Family: \(family)") // ファミリー。
                    }
                    if let families = details.families, !families.isEmpty {
                        Text("Families: \(families.joined(separator: ", "))") // ファミリーズ。
                    }
                    if let parameterSize = details.parameter_size {
                        Text("Parameter Size: \(parameterSize)") // パラメータサイズ。
                    }
                    if let quantizationLevel = details.quantization_level {
                        Text("Quantization Level: \(quantizationLevel)") // 量子化レベル。
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)
            } else {
                Text("No details available.") // 詳細情報はありません。
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.init(nsColor: .controlBackgroundColor)) // macOSの標準背景色
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
}

// SwiftUIのプレビュー用
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
