import SwiftUI
import AppKit // NSPasteboard のため

struct ModelListView: View {
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    @Binding var selectedModel: OllamaModel.ID? // 選択されたモデルのIDをバインディングで受け取ります
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>] // ソート順をバインディングで受け取ります

    @Binding var showingAddSheet: Bool // モデル追加シートの表示/非表示を制御するバインディング
    @Binding var showingDeleteConfirmation: Bool // 削除確認アラートの表示/非表示を制御するバインディング
    @Binding var modelToDelete: OllamaModel? // 削除対象のモデルを保持するバインディング

    // 現在のソート順に基づいてモデルリストを返すComputed Property
    var sortedModels: [OllamaModel] {
        executor.models.sorted(using: sortOrder)
    }

    // 各TableColumnのContentに適用するコンテキストメニューのヘルパービュー
    // このビューは各セルのコンテンツをラップし、コンテキストメニューを提供します
    @ViewBuilder
    private func contextMenuWrapper<Content: View>(for model: OllamaModel, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .leading) { // ZStackでセル全体をカバーします
            Color.clear // ZStackの背景として機能し、ヒット領域を確保します
            content() // 元のテキストコンテンツ
        }
        .frame(maxWidth: .infinity, alignment: .leading) // ZStackを列幅いっぱいに広げます
        .contentShape(Rectangle()) // コンテキストメニューのトリガー範囲をZStack全体に設定します
        .contextMenu { // コンテキストメニューの定義
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

    var body: some View {
        VStack {
            Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
                // 「番号」列: 最小30、理想50、最大無制限
                TableColumn("No.", value: \.originalIndex) { model in // テーブル列ヘッダー：番号。
                    contextMenuWrapper(for: model) {
                        // 0-based indexを1-basedで表示します
                        Text("\(model.originalIndex + 1)")
                    }
                }
                .width(min: 30, ideal: 50, max: .infinity) // 番号列の幅設定を更新します

                // 「名前」列: 最小50、理想150、最大無制限
                TableColumn("Name", value: \.name) { model in // テーブル列ヘッダー：名前。
                    contextMenuWrapper(for: model) {
                        Text(model.name)
                    }
                }
                .width(min: 100, ideal: 200, max: .infinity) // 名前列の幅設定を更新します

                // 「サイズ」列: 最小30、理想50、最大無制限
                TableColumn("Size", value: \.comparableSize) { model in // テーブル列ヘッダー：サイズ。
                    contextMenuWrapper(for: model) {
                        Text(model.formattedSize) // formattedSizeを使用します
                    }
                }
                .width(min: 50, ideal: 100, max: .infinity) // サイズ列の幅設定を更新します

                // 「変更日」列: 最小50、理想80、最大無制限
                TableColumn("Modified At", value: \.comparableModifiedDate) { model in // テーブル列ヘッダー：変更日。
                    contextMenuWrapper(for: model) {
                        Text(model.formattedModifiedAt) // formattedModifiedAtを使用します
                    }
                }
                .width(min: 100, ideal: 150, max: .infinity) // 変更日列の幅設定を更新します
            }
            .overlay {
                if executor.models.isEmpty && !executor.isRunning && !executor.isPulling { // pull中も表示されないように条件追加
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
            // PullProgressViewを抽出して型チェックの負担を軽減
            if executor.isPulling {
                PullProgressView(executor: executor)
            }

            // コマンド実行の出力表示（以前のTextEditor）
            // OutputTextViewを抽出して型チェックの負担を軽減
            OutputTextView(executor: executor)
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
        .padding(.vertical) // 上下のパディング
        .onAppear {
            print("ModelListView Appeared. Fetching Ollama models from API.") // デバッグ用
            // ビューが表示されたときにOllama APIからモデルリストを取得します
            Task {
                await executor.fetchOllamaModelsFromAPI()
            }
        }
    }
}

// MARK: - PullProgressView (抽出されたサブビュー)
struct PullProgressView: View {
    @ObservedObject var executor: CommandExecutor

    var body: some View {
        VStack {
            ProgressView(value: executor.pullProgress) {
                Text(executor.pullStatus)
            } currentValueLabel: {
                // String Catalogで認識されるようにNSLocalizedStringを使用してフォーマット文字列を取得し、String(format:)で適用します。
                // CVarArgへの明示的なキャストにより、コンパイラの型推論を助けます。
                let formatString = NSLocalizedString("%.1f%% completed (%@ / %@)", comment: "Download progress format string. Example: '50.0% completed (100MB / 200MB)'")
                
                Text(String(format: formatString,
                            executor.pullProgress * 100 as CVarArg,
                            ByteCountFormatter().string(fromByteCount: executor.pullCompleted) as CVarArg,
                            ByteCountFormatter().string(fromByteCount: executor.pullTotal) as CVarArg))
            }
            .progressViewStyle(.linear)
        }
        .padding()
    }
}

// MARK: - OutputTextView (抽出されたサブビュー)
struct OutputTextView: View {
    @ObservedObject var executor: CommandExecutor

    var body: some View {
        TextEditor(text: .constant(executor.output))
            .font(.footnote)
            .frame(height: 80) // 高さを制限します
            .padding(.horizontal)
            .scrollContentBackground(.hidden) // macOS 13以降で背景を隠します
            .background(Color.textEditorBackground) // カスタム背景色
            .cornerRadius(5) // 角を丸くします
            .padding([.horizontal, .bottom])
            .onChange(of: executor.output) { oldValue, newValue in // デバッグ用: 出力の変更を監視します
                print("Executor Output Changed (first 100 chars): \(newValue.prefix(100))...")
            }
    }
}


// SwiftUIのプレビュー用
struct ModelListView_Previews: PreviewProvider {
    @State static var selectedModel: OllamaModel.ID? = nil
    @State static var sortOrder: [KeyPathComparator<OllamaModel>] = [.init(\.originalIndex, order: .forward)]
    @State static var showingAddSheet = false
    @State static var showingDeleteConfirmation = false
    @State static var modelToDelete: OllamaModel? = nil

    static var previews: some View {
        ModelListView(
            executor: CommandExecutor(),
            selectedModel: $selectedModel,
            sortOrder: $sortOrder,
            showingAddSheet: $showingAddSheet,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            modelToDelete: $modelToDelete
        )
    }
}
