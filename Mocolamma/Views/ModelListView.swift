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
    case status = "Status"
    
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
    var executor: CommandExecutor
    @Environment(ServerManager.self) var serverManager
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    @Binding var selectedModel: OllamaModel.ID? // 選択されたモデルのIDをバインディングで受け取ります
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>] // ソート順をバインディングで受け取ります
    
    @Binding var showingAddSheet: Bool // モデル追加シートの表示/非表示を制御するバインディング
    @Binding var selectedFilterTag: String? // フィルター状態をバインディングで受け取ります
    @Binding var showingDeleteConfirmation: Bool // 削除確認アラートの表示/非表示を制御するバインディング
    @Binding var modelToDelete: OllamaModel? // 削除対象のモデルを保持するバインディング
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var inputAreaHeight: CGFloat = 0
    @State private var sortedAndFilteredModels: [OllamaModel] = [] // メモ化用の状態
    @State private var pullErrorMessage: String? = nil
    @State private var showingPullErrorAlert: Bool = false
    @State private var loadErrorMessage: String? = nil
    @State private var showingLoadErrorAlert: Bool = false
    let isSelected: Bool // 現在のタブが選択されているか
    
    let onTogglePreview: () -> Void // プレビューパネルをトグルするためのクロージャ
    
    // MARK: - Sorting State
    @State private var sortCriterion: SortCriterion = .number
    @State private var sortOrderOption: SortOrder = .ascending
    
    
    @State private var cachedAvailableTags: [String] = [] // タグ一覧のキャッシュ用ステータス
    
    // タグの表示順序を制御するための重み付け
    private func tagWeight(_ tag: String) -> Int {
        switch tag.lowercased() {
        case "completion": return 1
        case "thinking": return 2
        case "tools": return 3
        case "vision": return 4
        case "audio": return 5
        case "embedding": return 6
        case "image": return 7
        default: return 100
        }
    }
    
    // タグの表示名をローカライズして返すヘルパー
    private func localizedTagName(_ tag: String) -> String {
        switch tag.lowercased() {
        case "completion": return String(localized: "Completion")
        case "vision": return String(localized: "Vision")
        case "audio": return String(localized: "Audio")
        case "image": return String(localized: "Image")
        case "embedding": return String(localized: "Embedding")
        case "tools": return String(localized: "Tools")
        case "thinking": return String(localized: "Thinking")
        default: return tag.capitalized
        }
    }
    
    // タグのアイコン名を返すヘルパー
    private func tagIconName(_ tag: String) -> String {
        switch tag.lowercased() {
        case "completion": return "character.cursor.ibeam"
        case "vision": return "eye"
        case "audio": return "music.note"
        case "tools": return "wrench.and.screwdriver"
        case "thinking": return "brain.filled.head.profile"
        case "embedding": return "square.stack.3d.up"
        case "image": return "photo"
        default: return "tag"
        }
    }
    
    // 現在のフィルター状態に基づいたアイコン名を返す
    private var filterIconName: String {
        if let tag = selectedFilterTag {
            return tagIconName(tag)
        }
        return "line.3.horizontal.decrease"
    }
    
    // ソート項目のアイコン名を返す
    private func criterionIconName(_ criterion: SortCriterion) -> String {
        switch criterion {
        case .name: return "textformat"
        case .number: return "textformat.numbers"
        case .size: return "internaldrive"
        case .date: return "calendar"
        case .status: return "info.circle"
        }
    }
    
    // ソート順序のアイコン名を返す
    private func orderIconName(_ order: SortOrder) -> String {
        switch order {
        case .ascending: return "chevron.down.2"
        case .descending: return "chevron.up.2"
        }
    }
    
    // 現在のソート順とフィルターに基づいてモデルリストを更新するメソッド
    private func updateSortedAndFilteredModels() {
        let allModels = executor.models
        var models = allModels
        
        // フィルタリング適用
        if let filter = selectedFilterTag {
            models = models.filter { $0.capabilities?.contains(filter) ?? false }
        }
        
        // 全プラットフォームでTable/Menuから供給されるsortOrderに従ってソート
        sortedAndFilteredModels = models.sorted(using: sortOrder)
        
        // タグ一覧のキャッシュを更新
        let tags = allModels.compactMap { $0.capabilities }.flatMap { $0 }
        cachedAvailableTags = Array(Set(tags)).sorted { tag1, tag2 in
            tagWeight(tag1) < tagWeight(tag2)
        }
    }
    
    // Menuでの選択内容をsortOrderバインディングに同期するメソッド
    private func updateSortOrder() {
        let order: Foundation.SortOrder = sortOrderOption == .ascending ? .forward : .reverse
        switch sortCriterion {
        case .number:
            sortOrder = [KeyPathComparator(\.originalIndex, order: order)]
        case .name:
            sortOrder = [KeyPathComparator(\.name, order: order)]
        case .size:
            sortOrder = [KeyPathComparator(\.comparableSize, order: order)]
        case .date:
            sortOrder = [KeyPathComparator(\.comparableModifiedDate, order: order)]
        case .status:
            sortOrder = [KeyPathComparator(\.statusWeight, order: order)]
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
    
    
    private func parseError(from output: String, replaceNewline: Bool = true) -> String? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return replaceNewline ? err.replacingOccurrences(of: "\n", with: " ") : err
        }
        if output.lowercased().contains("error") {
            return replaceNewline ? output.replacingOccurrences(of: "\n", with: " ") : output
        }
        return nil
    }
    
    @ToolbarContentBuilder
    private var modelToolbarContent: some ToolbarContent {
#if os(macOS) || os(visionOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil)
        }
#endif

#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Filter", selection: $selectedFilterTag) {
                    Label("All Models", systemImage: "tray.full").tag(nil as String?)
                    ForEach(cachedAvailableTags, id: \.self) { tag in
                        Label(localizedTagName(tag), systemImage: tagIconName(tag)).tag(tag as String?)
                    }
                }
                .labelStyle(.titleAndIcon)
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: filterIconName)
            }
            .accessibilityLabel("Filter")
            .disabled(executor.isRunning || serverManager.selectedServer == nil || executor.apiConnectionError)
        }
#else
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: $sortCriterion) {
                    ForEach(SortCriterion.allCases) { criterion in
                        Label(LocalizedStringKey(criterion.rawValue), systemImage: criterionIconName(criterion)).tag(criterion)
                    }
                }
                Divider()
                Menu {
                    Picker("Filter", selection: $selectedFilterTag) {
                        Label("All Models", systemImage: "tray.full").tag(nil as String?)
                        ForEach(cachedAvailableTags, id: \.self) { tag in
                            Label(localizedTagName(tag), systemImage: tagIconName(tag)).tag(tag as String?)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: filterIconName)
                }
                Divider()
                Picker("Order", selection: $sortOrderOption) {
                    ForEach(SortOrder.allCases) { order in
                        Label(LocalizedStringKey(order.rawValue), systemImage: orderIconName(order)).tag(order)
                    }
                }
            } label: {
                Label("Sort", systemImage: filterIconName)
            }
            .accessibilityLabel("Sort and Filter")
            .help(String(localized: "Sort and Filter"))
            .disabled(executor.isRunning || serverManager.selectedServer == nil || executor.apiConnectionError)
        }
#endif

#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showingAddSheet = true }) {
                Label("Add New", systemImage: "plus")
            }
            .accessibilityLabel("Add New Model")
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil || executor.apiConnectionError)
        }
        
#if !os(macOS)
        Group {
#if os(iOS)
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
#endif
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onTogglePreview() }) {
                    Label("Inspector", systemImage: (isNativeVisionOS || isiOSAppOnVision) ? "info.circle" : (horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing"))
                }
                .accessibilityLabel("Inspector")
            }
        }
#endif
    }
    
    var body: some View {
        let copyIconName = SFSymbol.copy

        Group {
#if os(visionOS)
            ModelListContentView(
                sortedModels: sortedAndFilteredModels,
                selectedModel: $selectedModel,
                sortOrder: $sortOrder,
                modelToDelete: $modelToDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                loadErrorMessage: $loadErrorMessage,
                showingLoadErrorAlert: $showingLoadErrorAlert,
                copyIconName: copyIconName,
                bottomInset: inputAreaHeight
            )
#elseif os(iOS)
            if #available(iOS 26.0, *) {
                // iOS 26.0以降：safeAreaBarを使用して進捗を表示
                ModelListContentView(
                    sortedModels: sortedAndFilteredModels,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    modelToDelete: $modelToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    loadErrorMessage: $loadErrorMessage,
                    showingLoadErrorAlert: $showingLoadErrorAlert,
                    copyIconName: copyIconName,
                    bottomInset: 0
                )
                .safeAreaBar(edge: .bottom) {
                    PullProgressView(executor: executor, isSelected: isSelected)
                }
            } else {
                // iOS 26.0未満：VStack内に配置
                VStack(spacing: 0) {
                    ModelListContentView(
                        sortedModels: sortedAndFilteredModels,
                        selectedModel: $selectedModel,
                        sortOrder: $sortOrder,
                        modelToDelete: $modelToDelete,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        loadErrorMessage: $loadErrorMessage,
                        showingLoadErrorAlert: $showingLoadErrorAlert,
                        copyIconName: copyIconName,
                        bottomInset: 0
                    )
                    
                    PullProgressView(executor: executor, isSelected: isSelected)
                }
            }
#else
            // macOS：常にVStack内に配置（TableではsafeAreaBarのボケが機能しないため）
            VStack(spacing: 0) {
                ModelListContentView(
                    sortedModels: sortedAndFilteredModels,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    modelToDelete: $modelToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    loadErrorMessage: $loadErrorMessage,
                    showingLoadErrorAlert: $showingLoadErrorAlert,
                    copyIconName: copyIconName,
                    bottomInset: 0
                )
                
                PullProgressView(executor: executor, isSelected: isSelected)
            }
#endif
        }
#if os(visionOS)
        .ornament(
            visibility: (executor.isPulling || executor.isPullingErrorHold) && isSelected ? .visible : .hidden,
            attachmentAnchor: .scene(.bottom),
            contentAlignment: .center
        ) {
            PullProgressView(executor: executor, isSelected: isSelected)
                .frame(width: 600)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .glassBackgroundEffect()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height / 2
                } action: { newValue in
                    inputAreaHeight = newValue
                }
        }
#endif
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
            // サーバーが選択されており、かつ初期フェッチが未完了の場合のみ自動リフレッシュを実行
            // これにより、タブ切り替えのたびにリロードが走るのを防ぎ、UIの快適性を向上させる
            if serverManager.selectedServer != nil && !executor.initialFetchCompleted && !executor.isRunning && !executor.isPulling {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    appRefreshTrigger.send()
                }
            }
            updateSortedAndFilteredModels()
        }
        .onChange(of: executor.models) { _, _ in updateSortedAndFilteredModels() }
        .onChange(of: selectedFilterTag) { _, _ in updateSortedAndFilteredModels() }
        .onChange(of: sortOrder) { _, _ in updateSortedAndFilteredModels() }
        .onChange(of: executor.isPullingErrorHold) { _, newValue in
            if newValue && executor.pullHasError {
                if let errorText = parseError(from: executor.output, replaceNewline: false) {
                    pullErrorMessage = errorText
                    showingPullErrorAlert = true
                }
            }
        }
        .onChange(of: sortCriterion) { _, _ in updateSortOrder() }
        .onChange(of: sortOrderOption) { _, _ in updateSortOrder() }
        .alert("Download Failed", isPresented: $showingPullErrorAlert) {
            Button("OK") { }
        } message: {
            if let errorMessage = pullErrorMessage {
                Text(errorMessage)
            } else {
                Text("An unknown error occurred during model download.")
            }
        }
        .alert("Load Failed", isPresented: $showingLoadErrorAlert) {
            Button("OK") { }
        } message: {
            if let errorMessage = loadErrorMessage {
                Text(errorMessage)
            } else {
                Text("An unknown error occurred during model load.")
            }
        }
    }
}

// MARK: - モデルリスト表示本体のサブビュー

/// リストおよびテーブルの表示を担うビュー。
/// 進捗更新などの頻繁な変更から隔離するため、表示に必要な最小限のデータのみを受け取ります。
struct ModelListContentView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ServerManager.self) var serverManager
    let sortedModels: [OllamaModel]
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var modelToDelete: OllamaModel?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var loadErrorMessage: String?
    @Binding var showingLoadErrorAlert: Bool
    let copyIconName: String
    var bottomInset: CGFloat = 0
    @State private var modelForCustomKeepAlive: OllamaModel?
    
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    
    var body: some View {
        Group {
#if !os(macOS)
        List(selection: $selectedModel) {
            ForEach(sortedModels) { model in
                ModelListRowView(
                    model: model,
                    isSelected: selectedModel == model.id,
                    isActionsDisabled: executor.isRunning || executor.isPulling || serverManager.selectedServer == nil,
                    copyIconName: copyIconName,
                    loadModel: { await executor.loadModel(modelName: $0, keepAlive: $1) },
                    unloadModel: { await executor.unloadModel(modelName: $0) },
                    onDelete: { modelToDelete = $0; showingDeleteConfirmation = true },
                    onCustomKeepAlive: { modelForCustomKeepAlive = $0 },
                    onCopy: { text in
#if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
#else
                        UIPasteboard.general.string = text
#endif
                    },
                    onError: { error in loadErrorMessage = error; showingLoadErrorAlert = true },
                    parseError: { parseError(from: $0) },
                    getExecutorOutput: { executor.output }
                )
                .equatable()
                .tag(model.id)
            }
            .onDelete { offsets in
                let modelsToDelete = offsets.map { sortedModels[$0] }
                if let model = modelsToDelete.first {
                    modelToDelete = model
                    showingDeleteConfirmation = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model List")
        .accessibilityIdentifier("model_list")
#if os(visionOS)
        .safeAreaInset(edge: .bottom) {
            if bottomInset > 0 {
                Color.clear
                    .frame(height: bottomInset)
            }
        }
#endif
        .refreshable {
            guard !executor.isPulling else { return }
            appRefreshTrigger.send()
        }
#else
        Table(sortedModels, selection: $selectedModel, sortOrder: $sortOrder) {
            TableColumn("No.", value: \.originalIndex) { model in
                Text("\(model.originalIndex + 1)")
                    .help("No. \(model.originalIndex + 1)")
            }
            .width(min: 20, ideal: 50, max: .infinity)
            
            TableColumn("Name", value: \.name) { model in
                Text(model.name)
                    .help(model.name)
            }
            .width(min: 80, ideal: 150, max: .infinity)
            
            TableColumn("Size", value: \.comparableSize) { model in
                Text(model.formattedSize)
                    .help("\(model.formattedSize), \(model.size) B")
            }
            .width(min: 50, ideal: 100, max: .infinity)
            
            TableColumn("Modified At", value: \.comparableModifiedDate) { model in
                Text(model.formattedModifiedAt)
                    .help(model.formattedModifiedAt)
            }
            .width(min: 80, ideal: 130, max: .infinity)
            
            TableColumn("Status", value: \.statusWeight) { model in
                ModelLoadStatusIconView(statusWeight: model.statusWeight)
            }
            .width(min: 20, ideal: 70, max: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model Table")
        .accessibilityIdentifier("model_table_macos")
        .contextMenu(forSelectionType: OllamaModel.ID.self) { selectedIDs in
            if let selectedID = selectedIDs.first,
               let model = sortedModels.first(where: { $0.id == selectedID }) {
                loadModelMenu(for: model)
                
                Button("Unload Model", systemImage: "tray.and.arrow.up") {
                    Task {
                        await executor.unloadModel(modelName: model.name)
                    }
                }
                .disabled(!executor.runningModels.contains(where: { $0.name == model.name || $0.name == "\(model.name):latest" }))
                
                Divider()
                
                Button("Copy Model Name", systemImage: copyIconName) {
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
        }
        .sheet(item: $modelForCustomKeepAlive) { model in
            CustomKeepAliveSheet(modelName: model.name, modelForCustomKeepAlive: $modelForCustomKeepAlive) { keepAlive in
                Task {
                    let success = await executor.loadModel(modelName: model.name, keepAlive: keepAlive)
                    if !success {
                        await MainActor.run {
                            if let errorText = parseError(from: executor.output) {
                                loadErrorMessage = errorText
                                showingLoadErrorAlert = true
                            }
                        }
                    }
                }
            }
#if os(iOS)
            .presentationBackground(Color(uiColor: .systemBackground))
#endif
        }
    }
    
    @ViewBuilder
    private func loadModelMenu(for model: OllamaModel) -> some View {
        Menu {
            Button("Load with Default Time") {
                Task {
                    let success = await executor.loadModel(modelName: model.name)
                    if !success {
                        await MainActor.run {
                            if let errorText = parseError(from: executor.output) {
                                loadErrorMessage = errorText
                                showingLoadErrorAlert = true
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // プリセット (1m, 3m, 5m, 10m, 15m, 30m, 1h, Indefinite)
            Group {
                Button(LocalizedStringKey(KeepAliveOption.m1.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("1m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.m3.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("3m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.m5.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("5m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.m10.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("10m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.m15.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("15m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.m30.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("30m"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.h1.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .string("1h"))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
                Button(LocalizedStringKey(KeepAliveOption.indefinite.rawValue)) {
                    Task {
                        let success = await executor.loadModel(modelName: model.name, keepAlive: .int(-1))
                        if !success {
                            await MainActor.run {
                                if let errorText = parseError(from: executor.output) {
                                    loadErrorMessage = errorText
                                    showingLoadErrorAlert = true
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Custom...") {
                modelForCustomKeepAlive = model
            }
            
        } label: {
            Label("Load Model", systemImage: "tray.and.arrow.down")
        }
    }
    
    private func parseError(from output: String, replaceNewline: Bool = true) -> String? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return replaceNewline ? err.replacingOccurrences(of: "\n", with: " ") : err
        }
        if output.lowercased().contains("error") {
            return replaceNewline ? output.replacingOccurrences(of: "\n", with: " ") : output
        }
        return nil
    }
}

// MARK: - モデルリスト行ビュー

/// 各モデル行を表示するビュー。行ごとの不必要な再描画を防ぐために独立させています。
struct ModelListRowView: View, Equatable {
    let model: OllamaModel
    let isSelected: Bool
    let isActionsDisabled: Bool
    let copyIconName: String
    
    var loadModel: (String, JSONValue?) async -> Bool
    var unloadModel: (String) async -> Bool
    var onDelete: (OllamaModel) -> Void
    var onCustomKeepAlive: (OllamaModel) -> Void
    var onCopy: (String) -> Void
    var onError: (String) -> Void
    var parseError: (String) -> String?
    var getExecutorOutput: () -> String
    
    // ModelListRowViewはmodelの内容が変わらない限り再描画されません
    // 依存関係が明確なプロパティのみを比較対象にします
    static func == (lhs: ModelListRowView, rhs: ModelListRowView) -> Bool {
        lhs.model.id == rhs.model.id && 
        lhs.model.statusWeight == rhs.model.statusWeight &&
        lhs.model.size == rhs.model.size &&
        lhs.model.modified_at == rhs.model.modified_at &&
        lhs.isActionsDisabled == rhs.isActionsDisabled &&
        lhs.isSelected == rhs.isSelected
    }
    
    // アクセシビリティ用のステータステキスト
    private var statusText: String {
        switch model.statusWeight {
        case 0: return String(localized: "Loaded", comment: "Accessibility status: Model is successfully loaded")
        case 1: return String(localized: "Loading", comment: "Accessibility status: Model is currently loading")
        case 2: return String(localized: "Loaded", comment: "Accessibility status: Model is already loaded")
        default: return String(localized: "Not Loaded", comment: "Accessibility status: Model is not loaded")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(model.originalIndex + 1)")
                .foregroundColor(.secondary)
                .frame(minWidth: 20, alignment: .center)
                .help("No. \(model.originalIndex + 1)")
            
            VStack(alignment: .leading) {
                Text(model.name)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .help(model.name)
                Text("\(model.formattedSize), \(model.formattedModifiedAt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            ModelLoadStatusIconView(statusWeight: model.statusWeight)
        }
        .accessibilityElement()
        .accessibilityLabel(model.name)
        .accessibilityValue(getAccessibilityValue())
        .accessibilityIdentifier("model_row_\(model.id)")
        .accessibilityInputLabels([model.name])
        .accessibilityAction(named: String(localized: "Load Model")) {
            Task {
                await loadModel(model.name, nil)
            }
        }
        .accessibilityAction(named: String(localized: "Copy Model Name")) {
            onCopy(model.name)
        }
        .accessibilityAction(named: String(localized: "Delete Model")) {
            onDelete(model)
        }
        .contextMenu {
            Menu {
                Button("Load with Default Time") {
                    Task {
                        let success = await loadModel(model.name, nil)
                        if !success {
                            if let errorText = parseError(getExecutorOutput()) {
                                await MainActor.run {
                                    onError(errorText)
                                }
                            }
                        }
                    }
                }
                .disabled(isActionsDisabled)
                
                Divider()
                
                Group {
                    Button(LocalizedStringKey(KeepAliveOption.m1.rawValue)) { loadWithTime("1m") }
                    Button(LocalizedStringKey(KeepAliveOption.m3.rawValue)) { loadWithTime("3m") }
                    Button(LocalizedStringKey(KeepAliveOption.m5.rawValue)) { loadWithTime("5m") }
                    Button(LocalizedStringKey(KeepAliveOption.m10.rawValue)) { loadWithTime("10m") }
                    Button(LocalizedStringKey(KeepAliveOption.m15.rawValue)) { loadWithTime("15m") }
                    Button(LocalizedStringKey(KeepAliveOption.m30.rawValue)) { loadWithTime("30m") }
                    Button(LocalizedStringKey(KeepAliveOption.h1.rawValue)) { loadWithTime("1h") }
                    Button(LocalizedStringKey(KeepAliveOption.indefinite.rawValue)) { loadWithTime("-1") }
                }
                .disabled(isActionsDisabled)
                
                Divider()
                
                Button("Custom...") {
                    onCustomKeepAlive(model)
                }
                .disabled(isActionsDisabled)
            } label: {
                Label("Load Model", systemImage: "tray.and.arrow.down")
            }
            
            Button("Unload Model", systemImage: "tray.and.arrow.up") {
                Task {
                    await unloadModel(model.name)
                }
            }
            .disabled(isActionsDisabled || model.statusWeight == 3) // ロード中でない場合は無効化
            
            Divider()
            
            Button {
                onCopy(model.name)
            } label: {
                Label("Copy Model Name", systemImage: copyIconName)
            }
            
            Button(role: .destructive) {
                onDelete(model)
            } label: {
                Label("Delete...", systemImage: "trash")
            }
            .disabled(isActionsDisabled)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete(model)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .disabled(isActionsDisabled)
        }
    }
    
    private func loadWithTime(_ time: String) {
        Task {
            let success: Bool
            if time == "-1" {
                success = await loadModel(model.name, .int(-1))
            } else {
                success = await loadModel(model.name, .string(time))
            }
            
            if !success {
                if let errorText = parseError(getExecutorOutput()) {
                    await MainActor.run {
                        onError(errorText)
                    }
                }
            }
        }
    }
    
    private func getAccessibilityValue() -> String {
        let activeSuffix = isSelected ? String(localized: ", Active Model") : ""
        return String(localized: "\(model.formattedSize), \(model.formattedModifiedAt), \(statusText)\(activeSuffix)")
    }
}

private func parseError(from output: String, replaceNewline: Bool = true) -> String? {
    if let data = output.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let err = obj["error"] as? String {
        return replaceNewline ? err.replacingOccurrences(of: "\n", with: " ") : err
    }
    if output.lowercased().contains("error") {
        return replaceNewline ? output.replacingOccurrences(of: "\n", with: " ") : output
    }
    return nil
}

// MARK: - モデルステータスアイコン用のサブビュー

/// モデルのロード状態を示すアイコンを表示する独立したビュー。
/// CommandExecutorを独自に監視することで、親ビューの再描画を防ぎ、リストスクロール時のCPU負荷を低減します。
struct ModelLoadStatusIconView: View {
    let statusWeight: Int
    
    var body: some View {
        ZStack {
            if statusWeight == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            } else if statusWeight == 1 {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else if statusWeight == 2 {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: statusWeight)
    }
}

// MARK: - 進捗表示用のサブビュー

/// モデルのプル進捗を表示するための独立したビュー。
/// CommandExecutorを独自に監視することで、進捗更新時の描画負荷をこのビュー内に限定します。
struct PullProgressView: View {
    var executor: CommandExecutor
    let isSelected: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var pullProgressString: String {
        let percentString = executor.pullProgress.formatted(.percent.precision(.fractionLength(1)))
        let completed = ByteCountFormatter().string(fromByteCount: executor.pullCompleted)
        let total = ByteCountFormatter().string(fromByteCount: executor.pullTotal)
        return String(localized: "\(percentString) completed (\(completed) / \(total))",
                      comment: "ダウンロードの進捗メッセージ。ダウンロード完了のパーセンテージ (ダウンロード中の容量 / 全体の容量)")
    }
    
    var body: some View {
        if (executor.isPulling || executor.isPullingErrorHold) && isSelected {
#if os(visionOS)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: executor.pullProgress) {
                        Text(executor.pullStatus)
                            .animation(nil, value: executor.pullStatus)
                    } currentValueLabel: {
                        progressLabels
                            .animation(nil, value: executor.pullProgress)
                    }
                    .progressViewStyle(.linear)
                    .animation(.default, value: executor.pullProgress)
                    
                    if let errorText = parseError(from: executor.output) {
                        MarqueeText(text: errorText)
                            .foregroundColor(.red)
                            .padding(.top, 2)
                            .frame(maxWidth: .infinity, minHeight: 14)
                    }
                }
                
                if executor.isPullingErrorHold && executor.pullHasError {
                    Button(action: {
                        if !executor.lastPulledModelName.isEmpty {
                            executor.pullModel(modelName: executor.lastPulledModelName)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Retry")
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Download Progress: \(executor.pullStatus)"))
            .accessibilityValue(pullProgressString)
#else
            VStack(alignment: .center, spacing: 8) {
                ProgressView(value: executor.pullProgress) {
                    HStack(alignment: .bottom) {
                        Text(executor.pullStatus)
                            .animation(nil, value: executor.pullStatus)
                        Spacer()
                        if executor.isPullingErrorHold && executor.pullHasError {
                            Button(action: {
                                if !executor.lastPulledModelName.isEmpty {
                                    executor.pullModel(modelName: executor.lastPulledModelName)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Retry")
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                            .contentShape(Rectangle())
                        }
                    }
                } currentValueLabel: {
                    progressLabels
                        .animation(nil, value: executor.pullProgress)
                }
                .progressViewStyle(.linear)
                .animation(.default, value: executor.pullProgress)
                
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
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Download Progress: \(executor.pullStatus)"))
            .accessibilityValue(pullProgressString)
#endif
        }
    }
    
    @ViewBuilder
    private var progressLabels: some View {
#if os(visionOS)
        HStack {
            Text(pullProgressString)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if executor.pullSpeedBytesPerSec > 0 {
                speedAndETASection
            }
        }
#else
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading) {
                Text(pullProgressString)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if executor.pullSpeedBytesPerSec > 0 {
                    speedAndETASection
                }
            }
        } else {
            HStack {
                Text(pullProgressString)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if executor.pullSpeedBytesPerSec > 0 {
                    speedAndETASection
                }
            }
        }
#endif
    }
    
    @ViewBuilder
    private var speedAndETASection: some View {
        let speedString = ByteCountFormatter.string(fromByteCount: Int64(executor.pullSpeedBytesPerSec), countStyle: .file)
        let eta = Int(executor.pullETARemaining)
        let etaMin = eta / 60
        let etaSec = eta % 60
        Text(String(format: NSLocalizedString("%@/s, Time Remaining: %02d:%02d", comment: "速度と残り時間表示。ダウンロード速度毎秒, Time Remaining: 分数:秒数"), speedString, etaMin, etaSec))
            .foregroundStyle(.secondary)
#if os(visionOS)
            .frame(maxWidth: .infinity, alignment: .trailing)
#else
            .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .compact ? .leading : .trailing)
#endif
    }
    
    private func parseError(from output: String, replaceNewline: Bool = true) -> String? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return replaceNewline ? err.replacingOccurrences(of: "\n", with: " ") : err
        }
        if output.lowercased().contains("error") {
            return replaceNewline ? output.replacingOccurrences(of: "\n", with: " ") : output
        }
        return nil
    }
}

// MARK: - カスタムKeep Alive指定用のシート

struct CustomKeepAliveSheet: View {
    let modelName: String
    @Binding var modelForCustomKeepAlive: OllamaModel?
    @State private var value: Int = 5
    @State private var unit: KeepAliveUnit = .minutes
    var onConfirm: (JSONValue) -> Void
    
    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            Text("Load with Duration")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("", value: $value, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                    
                    Stepper("", value: $value, in: 1...99999)
                        .labelsHidden()
                        .controlSize(.large)
                    
                    Picker("", selection: $unit) {
                        ForEach(KeepAliveUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                }
                
                Text("Specify how long the model will stay loaded into memory. Models can be unloaded at any time.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    modelForCustomKeepAlive = nil
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                
                Button("Load") {
                    let jsonVal = JSONValue.string("\(value)\(unit.rawValue)")
                    onConfirm(jsonVal)
                    modelForCustomKeepAlive = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300, minHeight: 100, maxHeight: 250)
#else
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    TextField("", value: $value, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: .infinity)
                    
                    Stepper("", value: $value, in: 1...99999)
                        .labelsHidden()
                    
                    Picker("", selection: $unit) {
                        ForEach(KeepAliveUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding()
                
                Text("Specify how long the model will stay loaded into memory. Models can be unloaded at any time.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Load with Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { modelForCustomKeepAlive = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") {
                        let jsonVal = JSONValue.string("\(value)\(unit.rawValue)")
                        onConfirm(jsonVal)
                        modelForCustomKeepAlive = nil
                    }
                    .bold()
                }
            }
        }
#endif
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
        selectedFilterTag: .constant(nil), // ダミーのBinding<String?>
        showingDeleteConfirmation: .constant(false), // ダミーのBinding<Bool>
        modelToDelete: .constant(nil), // ダミーのBinding<OllamaModel?>
        isSelected: true, // ダミーのisSelected
        onTogglePreview: { print("ModelListView_Previews: Dummy onTogglePreview called.") } // ダミーのクロージャ
    )
}
