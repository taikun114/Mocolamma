import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - ソート順序の定義

enum SortCriterion: String, CaseIterable, Identifiable {
    case number = "Number"
    case name = "Name"
    case size = "Size"
    case date = "Date"
    
    var id: String { self.rawValue }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"

    var id: String { self.rawValue }
}


// MARK: - モデルリストビュー

/// モデルのテーブル表示、ダウンロード進捗ゲージ、APIログ表示、
/// および再読み込み・モデル追加用のツールバーボタンなど、
/// モデルリストに関連するUIとロジックをカプセル化したビューです。
/// ContentViewから必要なデータとバインディングを受け取って表示を更新します。
struct ModelListView: View {
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @Binding var selectedModel: OllamaModel.ID? // 選択されたモデルのIDをバインディングで受け取ります
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>] // ソート順をバインディングで受け取ります
    
    @Binding var showingAddSheet: Bool // モデル追加シートの表示/非表示を制御するバインディング
    @Binding var showingDeleteConfirmation: Bool // 削除確認アラートの表示/非表示を制御するバインディング
    @Binding var modelToDelete: OllamaModel? // 削除対象のモデルを保持するバインディング
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let isSelected: Bool // 現在のタブが選択されているか

    let onTogglePreview: () -> Void // プレビューパネルをトグルするためのクロージャ

    // MARK: - Sorting State
    @State private var sortCriterion: SortCriterion = .number
    @State private var sortOrderOption: SortOrder = .ascending
    

    // 現在のソート順に基づいてモデルリストを返すComputed Property
    var sortedModels: [OllamaModel] {
        let models = executor.models
        let ascending = sortOrderOption == .ascending
        
        switch sortCriterion {
        case .number:
            return models.sorted {
                ascending ? $0.originalIndex < $1.originalIndex : $0.originalIndex > $1.originalIndex
            }
        case .name:
            return models.sorted {
                ascending ? $0.name < $1.name : $0.name > $1.name
            }
        case .size:
            return models.sorted {
                ascending ? $0.comparableSize < $1.comparableSize : $0.comparableSize > $1.comparableSize
            }
        case .date:
            return models.sorted {
                ascending ? $0.comparableModifiedDate < $1.comparableModifiedDate : $0.comparableModifiedDate > $1.comparableModifiedDate
            }
        }
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
    
    private func deleteModel(at offsets: IndexSet) {
        let modelsToDelete = offsets.map { sortedModels[$0] }
        if let model = modelsToDelete.first {
            modelToDelete = model
            showingDeleteConfirmation = true
        }
    }
    
    @ToolbarContentBuilder
    private var modelToolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                appRefreshTrigger.send()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil)
        }
        #endif

        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: $sortCriterion) {
                    ForEach(SortCriterion.allCases) {
                        criterion in
                        Text(LocalizedStringKey(criterion.rawValue)).tag(criterion)
                    }
                }
                Divider()
                Picker("Order", selection: $sortOrderOption) {
                    ForEach(SortOrder.allCases) {
                        order in
                        Text(LocalizedStringKey(order.rawValue)).tag(order)
                    }
                }
            } label: {
                Label("Sort", systemImage: "line.3.horizontal.decrease")
            }
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil || executor.apiConnectionError)
        }
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        #endif

        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                showingAddSheet = true
            }) {
                Label("Add New", systemImage: "plus")
            }
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil || executor.apiConnectionError)
        }

        #if os(iOS)
        Group { // 条件付きコンテンツをGroupでラップ
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onTogglePreview() }) {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        #endif
    }

    var body: some View {        VStack {
#if os(iOS)
        List(selection: $selectedModel) {
            ForEach(sortedModels) { model in
                HStack(alignment: .center, spacing: 16) {
                    Text("\(model.originalIndex + 1)")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 20, alignment: .center)
                        .help("No. \(model.originalIndex + 1)") // 番号のヘルプテキスト
                    
                    VStack(alignment: .leading) {
                        Text(model.name)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .help(model.name)
                        Text("\(model.formattedSize), \(model.formattedModifiedAt)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(model.id)
                .contextMenu {
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = model.name
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.name, forType: .string)
                        #endif
                    } label: {
                        Label("Copy Model Name", systemImage: "document.on.document")
                    }
                    
                    Button(role: .destructive) {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete...", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteModel)
        }
        .refreshable {
            appRefreshTrigger.send()
        }
#else
            Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
                TableColumn("No.", value: \.originalIndex) { model in // テーブル列ヘッダー：番号。
                    Text("\(model.originalIndex + 1)")
                        .help("No. \(model.originalIndex + 1)") // 番号のヘルプテキスト
                }
                .width(min: 30, ideal: 50, max: .infinity)

                TableColumn("Name", value: \.name) { model in // テーブル列ヘッダー：名前。
                    Text(model.name)
                        .help(model.name)
                }
                .width(min: 100, ideal: 200, max: .infinity)

                TableColumn("Size", value: \.comparableSize) { model in // テーブル列ヘッダー：サイズ。
                    Text(model.formattedSize) // formattedSizeを使用します
                        .help("\(model.formattedSize), \(model.size) B") // サイズのヘルプテキスト
                }
                .width(min: 50, ideal: 100, max: .infinity)

                TableColumn("Modified At", value: \.comparableModifiedDate) { model in // テーブル列ヘッダー：変更日。
                    Text(model.formattedModifiedAt) // formattedModifiedAtを使用します
                        .help(model.formattedModifiedAt) // 変更日のヘルプテキスト
                }
                .width(min: 100, ideal: 150, max: .infinity)
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
             if (executor.isPulling || executor.isPullingErrorHold) && isSelected {
                 VStack(alignment: .center, spacing: 8) {
                     ProgressView(value: executor.pullProgress) {
                         HStack(alignment: .bottom) {
                             Text(executor.pullStatus)
                             Spacer()
                             if executor.isPullingErrorHold && executor.pullHasError {
                                 Button(action: {
                                     if !executor.lastPulledModelName.isEmpty {
                                         executor.pullModel(modelName: executor.lastPulledModelName)
                                     }
                                 }) {
                                     Image(systemName: "arrow.clockwise")
                                         .help("Retry")
                                 }
                                 .buttonStyle(.plain)
                                 .padding(.top, 4)
                                 .padding(.bottom, 2)
                                 .contentShape(Rectangle())
                             }
                         }
                     } currentValueLabel: {
                         Group {
                             if horizontalSizeClass == .compact {
                                 VStack(alignment: .leading) {
                                     Text(String(format: NSLocalizedString(" %.1f%% completed (%@ / %@)", comment: "ダウンロードの進捗メッセージ。ダウンロード完了のパーセンテージ (ダウンロード中の容量 / 全体の容量)"),
                                                  executor.pullProgress * 100 as CVarArg,
                                                  ByteCountFormatter().string(fromByteCount: executor.pullCompleted) as CVarArg,
                                                  ByteCountFormatter().string(fromByteCount: executor.pullTotal) as CVarArg))
                                         .frame(maxWidth: .infinity, alignment: .leading)
                                     if executor.pullSpeedBytesPerSec > 0 {
                                         let speedString = ByteCountFormatter.string(fromByteCount: Int64(executor.pullSpeedBytesPerSec), countStyle: .file)
                                         let eta = Int(executor.pullETARemaining)
                                         let etaMin = eta / 60
                                         let etaSec = eta % 60
                                         Text(String(format: NSLocalizedString("%@/s, Time Remaining: %02d:%02d", comment: "速度と残り時間表示。ダウンロード速度毎秒, Time Remaining: 分数:秒数"), speedString, etaMin, etaSec))
                                             .foregroundStyle(.secondary)
                                             .frame(maxWidth: .infinity, alignment: .leading)
                                     }
                                 }
                             } else {
                                 HStack {
                                     Text(String(format: NSLocalizedString(" %.1f%% completed (%@ / %@)", comment: "ダウンロードの進捗メッセージ。ダウンロード完了のパーセンテージ (ダウンロード中の容量 / 全体の容量)"),
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
                                         Text(String(format: NSLocalizedString("%@/s, Time Remaining: %02d:%02d", comment: "速度と残り時間表示。ダウンロード速度毎秒, Time Remaining: 分数:秒数"), speedString, etaMin, etaSec))
                                             .foregroundStyle(.secondary)
                                             .frame(maxWidth: .infinity, alignment: .trailing)
                                     }
                                 }
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
                 .padding(.horizontal, 12)
                 .padding(.top, !(executor.isPullingErrorHold && executor.pullHasError) ? 6 : 0)
                 .padding(.bottom, 12)
             }
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
                    systemImage: "tray.full",
                    description: Text("No models are currently installed. Click or tap '+' to add a new model.")
                )
            } else if executor.isRunning {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(2)
            }
        }
        
        .navigationTitle("Models")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))

        .toolbar {
            modelToolbarContent
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled && !executor.isRunning && !executor.isPulling {
                appRefreshTrigger.send()
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
        isSelected: true, // ダミーのisSelected
        onTogglePreview: { print("ModelListView_Previews: Dummy onTogglePreview called.") } // ダミーのクロージャ
    )
}
