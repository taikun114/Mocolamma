import SwiftUI
#if os(macOS)
import AppKit // NSPasteboard のため
#endif

// MARK: - モデルリストビュー

/// モデルのテーブル表示、ダウンロード進捗ゲージ、APIログ表示、
/// および再読み込み・モデル追加用のツールバーボタンなど、
/// モデルリストに関連するUIとロジックをカプセル化したビューです。
/// ContentViewから必要なデータとバインディングを受け取って表示を更新します。
struct ModelListView: View {
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    @EnvironmentObject var serverManager: ServerManager
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

    // ナビゲーションのサブタイトルを生成するComputed Property
    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }

    
    private func parseError(from output: String) -> String? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return err.replacingOccurrences(of: "\n", with: " ")
        }
        if output.lowercased().contains("error") { return output.replacingOccurrences(of: "\n", with: " ") }
        return nil
    }
    
    var body: some View {        VStack {
            #if os(iOS)
            Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
                TableColumn("No.", value: \.originalIndex) { model in
                    Text("\(model.originalIndex + 1)")
                }
                .width(min: 30, ideal: 50, max: .infinity)
                TableColumn("Name", value: \.name) { model in
                    Text(model.name)
                }
                .width(min: 100, ideal: 200, max: .infinity)
                TableColumn("Size", value: \.comparableSize) { model in
                    Text(model.formattedSize)
                }
                .width(min: 50, ideal: 100, max: .infinity)
                TableColumn("Modified At", value: \.comparableModifiedDate) { model in
                    Text(model.formattedModifiedAt)
                }
                .width(min: 100, ideal: 150, max: .infinity)
            }
            .refreshable {
                executor.isPullingErrorHold = false
                executor.pullHasError = false
                executor.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
                executor.clearModelInfoCache()
                let previousSelection = selectedModel
                let selectedServerID = serverManager.selectedServerID
                selectedModel = nil
                await executor.fetchOllamaModelsFromAPI()
                if let sid = selectedServerID { serverManager.updateServerConnectionStatus(serverID: sid, status: nil) }
                await MainActor.run {
                    serverManager.inspectorRefreshToken = UUID()
                    NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
                }
                if let prev = previousSelection, executor.models.contains(where: { $0.id == prev }) {
                    selectedModel = prev
                }
            }
            #else
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
                if let selectedID = selectedIDs.first,
                   let model = sortedModels.first(where: { $0.id == selectedID }) {
                    Button("Copy Model Name", systemImage: "document.on.document") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.name, forType: .string)
                    }


                    Button("Delete...", systemImage: "trash", role: .destructive) {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    }

                }
            }
            #endif
            // プログレスバーとステータステキスト
             if executor.isPulling || executor.isPullingErrorHold { 
                 VStack(alignment: .leading, spacing: 8) {
                     ProgressView(value: executor.pullProgress) {
                         Text(executor.pullStatus)
                     } currentValueLabel: {
                         HStack {
                             Text(String(format: NSLocalizedString(" %.1f%% completed (%@ / %@)", comment: "ダウンロード進捗: 完了/合計。"),
                                         executor.pullProgress * 100 as CVarArg,
                                         ByteCountFormatter().string(fromByteCount: executor.pullCompleted) as CVarArg,
                                         ByteCountFormatter().string(fromByteCount: executor.pullTotal) as CVarArg))
                                 .frame(maxWidth: .infinity, alignment: .leading)
                             Spacer()
                             if executor.pullSpeedBytesPerSec > 0 {
                                 let speedString = ByteCountFormatter.string(fromByteCount: Int64(executor.pullSpeedBytesPerSec), countStyle: .file)
                                 let eta = Int(executor.pullETARemaining)
                                 let etaMin = eta / 60
                                 let etaSec = eta % 60
                                 Text(String(format: NSLocalizedString("%@/s, Time Remaining: %02d:%02d", comment: "速度と残り時間表示。"), speedString, etaMin, etaSec))
                                     .foregroundStyle(.secondary)
                                     .frame(maxWidth: .infinity, alignment: .trailing)
                             }
                         }
                     }
                     .progressViewStyle(.linear)
                     if let errorText = parseError(from: executor.output) {
                         MarqueeText(text: errorText)
                             .foregroundColor(.red)
                             .padding(.top, 2)
                             .frame(maxWidth: .infinity, minHeight: 14)
                     }
                 }
                 .padding()
             }            // コマンド実行の出力表示 (TextEditorは削除されました)
        }
        .overlay(alignment: .center) {
            if serverManager.selectedServer == nil {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "server.rack",
                    description: Text("Please select a server in the Server tab.")
                )
            } else if executor.apiConnectionError {
                ContentUnavailableView(
                    "Connection Failed",
                    systemImage: "network.slash",
                    description: Text("Failed to connect to the Ollama API. Please check your network connection or server settings.")
                )
            } else if executor.models.isEmpty && !executor.isRunning && !executor.isPulling {
                ContentUnavailableView(
                    "No Models Available",
                    systemImage: "internaldrive.fill",
                    description: Text("No models are currently installed. Click '+' to add a new model.")
                )
            } else if executor.isRunning {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(2)
            }
        }
        .navigationTitle("Models")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))

        .toolbar { // ここで全てのToolbarItemをまとめます
            #if os(macOS)
            // MARK: - Reload Button (Primary Action, before Add New)
            ToolbarItem(placement: .primaryAction) { // primaryActionに配置
                 Button(action: {
                     Task {
                          executor.isPullingErrorHold = false
                          executor.pullHasError = false
                          executor.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
                           executor.clearModelInfoCache()
                          let previousSelection = selectedModel
                          let selectedServerID = serverManager.selectedServerID
                         selectedModel = nil
                         await executor.fetchOllamaModelsFromAPI()
                         if let sid = selectedServerID { serverManager.updateServerConnectionStatus(serverID: sid, status: nil) }
                         await MainActor.run {
                             serverManager.inspectorRefreshToken = UUID()
                             NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
                         }
                         if let prev = previousSelection, executor.models.contains(where: { $0.id == prev }) {
                             selectedModel = prev
                         }
                     }
                 }) {                    Label("Refresh", systemImage: "arrow.clockwise") // ツールバーボタン：モデルを更新します。
                }
                .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil)
            }
#endif
            // MARK: - Add Model Button (Primary Action)
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add New", systemImage: "plus")
                }
                .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil || executor.apiConnectionError)
            }
#if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onTogglePreview() }) {
                    Label("Inspector", systemImage: "info.circle")
                }
            }
#endif
        }
        // .padding(.vertical) // 上下のパディングを削除 (これはModelListViewのものです)
        .onAppear {
            print("ModelListView Appeared. Fetching Ollama models from API.")
            if !executor.isRunning && !executor.isPulling {
                let previousSelection = selectedModel
                Task {
                    await executor.fetchOllamaModelsFromAPI()
                    let models = executor.models
                    if let prev = previousSelection, models.contains(where: { $0.id == prev }) {
                        if selectedModel != prev { selectedModel = prev }
                    } else {
                        selectedModel = nil
                    }
                }
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
