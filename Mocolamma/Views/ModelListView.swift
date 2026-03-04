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
    var executor: CommandExecutor // @ObservedObjectを削除
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    @Binding var selectedModel: OllamaModel.ID? // 選択されたモデルのIDをバインディングで受け取ります
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>] // ソート順をバインディングで受け取ります
    
    @Binding var showingAddSheet: Bool // モデル追加シートの表示/非表示を制御するバインディング
    @Binding var selectedFilterTag: String? // フィルター状態をバインディングで受け取ります
    @Binding var showingDeleteConfirmation: Bool // 削除確認アラートの表示/非表示を制御するバインディング
    @Binding var modelToDelete: OllamaModel? // 削除対象のモデルを保持するバインディング
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var inputAreaHeight: CGFloat = 0
    @State private var pullErrorMessage: String? = nil
    @State private var showingPullErrorAlert: Bool = false
    let isSelected: Bool // 現在のタブが選択されているか
    
    let onTogglePreview: () -> Void // プレビューパネルをトグルするためのクロージャ
    
    // MARK: - Sorting State
    @State private var sortCriterion: SortCriterion = .number
    @State private var sortOrderOption: SortOrder = .ascending
    
    
    // 利用可能な全てのタグ（能力）を抽出して指定された順序でソートしたリスト
    private var availableTags: [String] {
        let tags = executor.models.compactMap { $0.capabilities }.flatMap { $0 }
        return Array(Set(tags)).sorted { tag1, tag2 in
            tagWeight(tag1) < tagWeight(tag2)
        }
    }
    
    // タグの表示順序を制御するための重み付け
    private func tagWeight(_ tag: String) -> Int {
        switch tag.lowercased() {
        case "completion": return 1
        case "thinking": return 2
        case "tools": return 3
        case "vision": return 4
        case "embedding": return 5
        case "image": return 6
        default: return 100
        }
    }
    
    // タグの表示名をローカライズして返すヘルパー
    private func localizedTagName(_ tag: String) -> String {
        switch tag.lowercased() {
        case "completion": return String(localized: "Completion")
        case "vision": return String(localized: "Vision")
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
        }
    }
    
    // ソート順序のアイコン名を返す
    private func orderIconName(_ order: SortOrder) -> String {
        switch order {
        case .ascending: return "chevron.down.2"
        case .descending: return "chevron.up.2"
        }
    }
    
    // 現在のソート順とフィルターに基づいてモデルリストを返すComputed Property
    var sortedModels: [OllamaModel] {
        var models = executor.models
        
        // フィルタリング適用
        if let filter = selectedFilterTag {
            models = models.filter { $0.capabilities?.contains(filter) ?? false }
        }
        
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
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Filter", selection: $selectedFilterTag) {
                    Label("All Models", systemImage: "tray.full").tag(nil as String?)
                    ForEach(availableTags, id: \.self) { tag in
                        Label(localizedTagName(tag), systemImage: tagIconName(tag)).tag(tag as String?)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: filterIconName)
            }
            .disabled(executor.isRunning || serverManager.selectedServer == nil || executor.apiConnectionError)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { appRefreshTrigger.send() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(executor.isRunning || executor.isPulling || serverManager.selectedServer == nil)
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
                        ForEach(availableTags, id: \.self) { tag in
                            Label(localizedTagName(tag), systemImage: tagIconName(tag)).tag(tag as String?)
                        }
                    }
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
            }
        }
#endif
    }
    
    var body: some View {
        let copyIconName = SFSymbol.copy

        Group {
#if os(visionOS)
            ModelListContentView(
                sortedModels: sortedModels,
                selectedModel: $selectedModel,
                sortOrder: $sortOrder,
                modelToDelete: $modelToDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                copyIconName: copyIconName,
                bottomInset: inputAreaHeight
            )
#elseif os(iOS)
            if #available(iOS 26.0, *) {
                // iOS 26.0以降：safeAreaBarを使用して進捗を表示
                ModelListContentView(
                    sortedModels: sortedModels,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    modelToDelete: $modelToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
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
                        sortedModels: sortedModels,
                        selectedModel: $selectedModel,
                        sortOrder: $sortOrder,
                        modelToDelete: $modelToDelete,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
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
                    sortedModels: sortedModels,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    modelToDelete: $modelToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
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
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled && !executor.isRunning && !executor.isPulling {
                appRefreshTrigger.send()
            }
        }
        .onChange(of: executor.isPullingErrorHold) { _, newValue in
            if newValue && executor.pullHasError {
                if let errorText = parseError(from: executor.output, replaceNewline: false) {
                    pullErrorMessage = errorText
                    showingPullErrorAlert = true
                }
            }
        }
        .alert("Download Failed", isPresented: $showingPullErrorAlert) {
            Button("OK") { }
        } message: {
            if let errorMessage = pullErrorMessage {
                Text(errorMessage)
            } else {
                Text("An unknown error occurred during model download.")
            }
        }
    }
}

// MARK: - モデルリスト表示本体のサブビュー

/// リストおよびテーブルの表示を担うビュー。
/// 進捗更新などの頻繁な変更から隔離するため、表示に必要な最小限のデータのみを受け取ります。
struct ModelListContentView: View {
    @Environment(CommandExecutor.self) var executor
    let sortedModels: [OllamaModel]
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var modelToDelete: OllamaModel?
    @Binding var showingDeleteConfirmation: Bool
    let copyIconName: String
    var bottomInset: CGFloat = 0
    
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    
    var body: some View {
#if !os(macOS)
        List(selection: $selectedModel) {
            ForEach(sortedModels) { model in
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
                }
                .tag(model.id)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = model.name
                    } label: {
                        Label("Copy Model Name", systemImage: copyIconName)
                    }
                    
                    Button(role: .destructive) {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete...", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .onDelete { offsets in
                let modelsToDelete = offsets.map { sortedModels[$0] }
                if let model = modelsToDelete.first {
                    modelToDelete = model
                    showingDeleteConfirmation = true
                }
            }
        }
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
            .width(min: 30, ideal: 50, max: .infinity)
            
            TableColumn("Name", value: \.name) { model in
                Text(model.name)
                    .help(model.name)
            }
            .width(min: 100, ideal: 200, max: .infinity)
            
            TableColumn("Size", value: \.comparableSize) { model in
                Text(model.formattedSize)
                    .help("\(model.formattedSize), \(model.size) B")
            }
            .width(min: 50, ideal: 100, max: .infinity)
            
            TableColumn("Modified At", value: \.comparableModifiedDate) { model in
                Text(model.formattedModifiedAt)
                    .help(model.formattedModifiedAt)
            }
            .width(min: 100, ideal: 150, max: .infinity)
        }
        .contextMenu(forSelectionType: OllamaModel.ID.self) { selectedIDs in
            if let selectedID = selectedIDs.first,
               let model = sortedModels.first(where: { $0.id == selectedID }) {
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
}

// MARK: - 進捗表示用のサブビュー

/// モデルのプル進捗を表示するための独立したビュー。
/// CommandExecutorを独自に監視することで、進捗更新時の描画負荷をこのビュー内に限定します。
struct PullProgressView: View {
    var executor: CommandExecutor
    let isSelected: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        if (executor.isPulling || executor.isPullingErrorHold) && isSelected {
#if os(visionOS)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: executor.pullProgress) {
                        Text(executor.pullStatus)
                    } currentValueLabel: {
                        progressLabels
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
                            .help("Retry")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
            }
#else
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
                    progressLabels
                }
                .progressViewStyle(.linear)
                .animation(.default, value: executor.pullProgress) // アニメーションを追加
                
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
#endif
        }
    }
    
    @ViewBuilder
    private var progressLabels: some View {
        let completed = ByteCountFormatter().string(fromByteCount: executor.pullCompleted)
        let total = ByteCountFormatter().string(fromByteCount: executor.pullTotal)
        let percent = executor.pullProgress * 100
        
        let progressString = String(format: NSLocalizedString(" %.1f%% completed (%@ / %@)", comment: "ダウンロードの進捗メッセージ。ダウンロード完了のパーセンテージ (ダウンロード中の容量 / 全体の容量)"),
                                    percent as CVarArg, completed as CVarArg, total as CVarArg)
        
#if os(visionOS)
        HStack {
            Text(progressString)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if executor.pullSpeedBytesPerSec > 0 {
                speedAndETASection
            }
        }
#else
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading) {
                Text(progressString)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if executor.pullSpeedBytesPerSec > 0 {
                    speedAndETASection
                }
            }
        } else {
            HStack {
                Text(progressString)
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
