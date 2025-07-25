import SwiftUI

struct ContentView: View {
    @ObservedObject var executor = CommandExecutor() // CommandExecutorのインスタンス
    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    @State private var showingAddSheet = false // モデル追加シートの表示/非表示を制御
    @State private var showingDeleteConfirmation = false // 削除確認アラートの表示/非表示を制御
    @State private var modelToDelete: OllamaModel? // 削除対象のモデルを保持
    
    // ソート順を保持するState変数
    // デフォルトでは「番号」の昇順でソートされるように変更
    @State private var sortOrder: [KeyPathComparator<OllamaModel>] = [
        .init(\.originalIndex, order: .forward)
    ]

    // 現在のソート順に基づいてモデルリストを返すComputed Property
    var sortedModels: [OllamaModel] {
        executor.models.sorted(using: sortOrder)
    }

    // 各TableColumnのContentに適用するコンテキストメニューのヘルパービュー
    // このビューは各セルのコンテンツをラップし、コンテキストメニューを提供します
    @ViewBuilder
    private func contextMenuWrapper<Content: View>(for model: OllamaModel, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .leading) { // ZStackでセル全体をカバー
            Color.clear // ZStackの背景として機能し、ヒット領域を確保
            content() // 元のテキストコンテンツ
        }
        .frame(maxWidth: .infinity, alignment: .leading) // ZStackを列幅いっぱいに広げる
        .contentShape(Rectangle()) // ヒットテスト領域を四角形にする
        .contextMenu { // コンテキストメニューをZStackに適用
            Button("モデル名をコピー") {
                // モデル名をクリップボードにコピーする
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.name, forType: .string)
                print("Copied model name: \(model.name)") // デバッグログ
            }
            
            Button("削除...") {
                print("Context menu triggered for model: \(model.name)") // デバッグログ
                modelToDelete = model // 右クリックされたモデルを直接セット
                showingDeleteConfirmation = true // 確認アラートを表示
            }
        }
    }

    var body: some View {
        HSplitView { // テーブルと詳細パネルを水平に分割
            // 左側のモデルリスト（Tableビュー）
            Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
                // 「番号」列: 最小30、理想50、最大無制限
                TableColumn("番号", value: \.originalIndex) { model in
                    contextMenuWrapper(for: model) {
                        // 0-based indexを1-basedで表示
                        Text("\(model.originalIndex + 1)")
                    }
                }
                .width(min: 30, ideal: 50, max: .infinity) // 番号列の幅設定を更新

                // 「名前」列: 最小50、理想150、最大無制限
                TableColumn("名前", value: \.name) { model in
                    contextMenuWrapper(for: model) {
                        Text(model.name)
                    }
                }
                .width(min: 100, ideal: 200, max: .infinity) // 名前列の幅設定を更新

                // 「サイズ」列: 最小30、理想50、最大無制限
                TableColumn("サイズ", value: \.comparableSize) { model in
                    contextMenuWrapper(for: model) {
                        Text(model.formattedSize) // formattedSizeを使用
                    }
                }
                .width(min: 50, ideal: 100, max: .infinity) // サイズ列の幅設定を更新

                // 「変更日」列: 最小50、理想80、最大無制限
                TableColumn("変更日", value: \.comparableModifiedDate) { model in
                    contextMenuWrapper(for: model) {
                        Text(model.formattedModifiedAt) // formattedModifiedAtを使用
                    }
                }
                .width(min: 100, ideal: 150, max: .infinity) // 変更日列の幅設定を更新
            }
            .background(Color.clear) // 背景色を透明にしてシステム標準に合わせる
            .frame(minWidth: 400) // テーブルの最小幅を設定
            .toolbar { // ツールバーにボタンを追加
                // MARK: - Reload Button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // 修正: async関数をTaskでラップする
                        Task {
                            await executor.fetchOllamaModelsFromAPI() // モデルリストを再読み込み
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh model list") // ツールチップ
                }
                // MARK: - Add Model Button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add new model") // ツールチップ
                }
            }
            .sheet(isPresented: $showingAddSheet) { // シートの表示
                AddModelSheetView(showingAddSheet: $showingAddSheet, executor: executor)
            }
            // MARK: - Delete Confirmation Alert (remains on ContentView)
            .alert("モデルの削除", isPresented: $showingDeleteConfirmation) {
                Button("キャンセル", role: .cancel) {
                    modelToDelete = nil // 削除対象モデルをクリア
                }
                Button("削除", role: .destructive) {
                    if let model = modelToDelete {
                        // 修正: async関数をTaskでラップする
                        Task {
                            await executor.deleteModel(modelName: model.name)
                        }
                        selectedModel = nil // 選択を解除
                        modelToDelete = nil // 削除対象モデルをクリア
                    }
                }
            } message: {
                if let model = modelToDelete {
                    Text("本当にモデル '\(model.name)' を削除しますか？\nこの操作は元に戻せません。")
                } else {
                    Text("選択されたモデルがありません。") // 理論上はここには来ないが、念のため
                }
            }

            // 右側の詳細表示パネル
            if let selectedModelID = selectedModel,
               let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                ModelDetailsView(model: model)
                    .frame(minWidth: 300) // 詳細パネルの最小幅を設定
            } else {
                Text("モデルを選択してください")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.vertical) // 上下のパディング
        .onAppear {
            print("ContentView Appeared. Fetching Ollama models from API.") // デバッグ用
            // アプリ起動時にollama APIからモデルリストを取得
            // 修正: async関数をTaskでラップする
            Task {
                await executor.fetchOllamaModelsFromAPI()
            }
        }
        
        // MARK: - ダウンロード状況表示エリア
        // テーブルと詳細パネルの下に配置
        VStack(alignment: .leading, spacing: 5) {
            if executor.isPulling {
                Text("ダウンロード状況: \(executor.pullStatus)")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                ProgressView(value: executor.pullProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 10)
                
                // ダウンロード中のファイルサイズ表示
                if executor.pullTotal > 0 {
                    Text("\(ByteCountFormatter().string(fromByteCount: executor.pullCompleted)) / \(ByteCountFormatter().string(fromByteCount: executor.pullTotal))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // APIフェッチのログ表示エリア（以前のTextEditor）
            TextEditor(text: .constant(executor.output))
                .font(.footnote)
                .frame(height: 100) // 高さを制限
                .padding(.horizontal)
                .scrollContentBackground(.hidden) // macOS 13以降でTextEditorの背景を透明にするための修飾子
                .background(Color.black.opacity(0.8)) // ターミナル風の背景色
                .foregroundColor(.white) // テキストの色
                .cornerRadius(8) // 角を丸くする
                .padding([.bottom, .horizontal])
                .onChange(of: executor.output) { oldValue, newValue in // デバッグ用にoutputの変化を監視
                    print("Executor Output Changed (first 100 chars): \(newValue.prefix(100))...")
                }
        }
        .padding([.horizontal, .top]) // HStack全体のパディング
    }
}

/// モデルの詳細情報を表示するビュー (変更なし)
struct ModelDetailsView: View {
    let model: OllamaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("モデル詳細")
                .font(.title2)
                .bold()
                .padding(.bottom, 5)

            Divider()

            Group {
                HStack {
                    Text("名前:")
                        .bold()
                    Text(model.name)
                }
                HStack {
                    Text("モデル名:")
                        .bold()
                    Text(model.model)
                }
                HStack {
                    Text("サイズ:")
                        .bold()
                    Text(model.formattedSize)
                }
                HStack {
                    Text("変更日:")
                        .bold()
                    Text(model.formattedModifiedAt)
                }
                HStack {
                    Text("ダイジェスト:")
                        .bold()
                    Text(model.digest)
                }
            }
            .font(.body)
            .padding(.horizontal)

            Divider()

            Text("詳細情報 (Details):")
                .font(.headline)
                .padding(.horizontal)

            if let details = model.details { // ここでOptionalをアンラップ
                VStack(alignment: .leading, spacing: 5) {
                    if let parentModel = details.parent_model, !parentModel.isEmpty {
                        Text("親モデル: \(parentModel)")
                    }
                    if let format = details.format {
                        Text("フォーマット: \(format)")
                    }
                    if let family = details.family {
                        Text("ファミリー: \(family)")
                    }
                    if let families = details.families, !families.isEmpty {
                        Text("ファミリーズ: \(families.joined(separator: ", "))")
                    }
                    if let parameterSize = details.parameter_size {
                        Text("パラメータサイズ: \(parameterSize)")
                    }
                    if let quantizationLevel = details.quantization_level {
                        Text("量子化レベル: \(quantizationLevel)")
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)
            } else {
                Text("詳細情報はありません。")
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

/// モデル追加用のシートビュー
struct AddModelSheetView: View {
    @Binding var showingAddSheet: Bool
    @ObservedObject var executor: CommandExecutor
    @State private var modelNameInput: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("モデルの追加")
                .font(.title)
                .bold()

            Text("追加したいモデル名を入力してください。")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("例: llama3, mistral", text: $modelNameInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            HStack {
                Button("キャンセル") {
                    showingAddSheet = false
                }
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button("追加") {
                    if !modelNameInput.isEmpty {
                        executor.pullModel(modelName: modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        showingAddSheet = false // シートを閉じる
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

// SwiftUIのプレビュー用
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
