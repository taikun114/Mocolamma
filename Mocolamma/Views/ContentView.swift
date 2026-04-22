import SwiftUI
import Foundation
import CompactSlider
import Combine

// MARK: - コンテンツビュー

/// アプリのメインウィンドウを構成するSwiftUIビューです。
/// プラットフォームに応じて、NavigationSplitViewまたはTabViewを使用してUIを構築します。
struct ContentView: View {
    // ServerManagerのインスタンスをAppStateに保持し、ライフサイクル全体で利用可能にする
    var serverManager: ServerManager
    // CommandExecutorはServerManagerに依存するため、後から初期化
    @State var executor: CommandExecutor
    
    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    // サイドバー/タブの選択状態をAppレベルから受け取ります
    @Binding var selection: String?
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    @State private var columnVisibility: NavigationSplitViewVisibility = .all // デフォルトで全パネル表示
    
    @Binding var showingInspector: Bool
    @Environment(ChatSettings.self) var chatSettings
    
    // モデル追加シートの表示/非表示を制御します
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingAddServerSheet: Bool
    @State private var showingDeleteConfirmation = false // 削除確認アラートの表示/非表示を制御します
    @State private var modelToDelete: OllamaModel? // 削除対象のモデルを保持します
    
    private var modelSettings = ModelSettingsManager.shared
    
    // フィルター状態を保持するState変数
    @State private var selectedFilterTag: String? = nil
    
    // 現在のソート順に基づいてモデルリストを保持するState変数
    @State private var sortedModels: [OllamaModel] = []
    
    // モデルリストを更新するメソッド
    private func updateSortedModels() {
        let models = executor.models.sorted(using: modelSettings.modelListSortOrder)
        if sortedModels != models {
            sortedModels = models
        }
    }
    
    // MARK: - Server Inspector related states
    @State private var selectedServerForInspector: ServerInfo? // Inspectorに表示するサーバー情報
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    
    // ContentViewの初期化子を更新
    init(serverManager: ServerManager, executor: CommandExecutor, selection: Binding<String?>, showingInspector: Binding<Bool>, showingAddModelsSheet: Binding<Bool>, showingAddServerSheet: Binding<Bool>, shouldClearChat: Binding<Bool>, shouldClearGeneration: Binding<Bool>, isPulling: Binding<Bool>) {
        self.serverManager = serverManager
        self.executor = executor
        self._selection = selection
        self._showingInspector = showingInspector
        self._showingAddModelsSheet = showingAddModelsSheet
        self._showingAddServerSheet = showingAddServerSheet
        self._shouldClearChat = shouldClearChat
        self._shouldClearGeneration = shouldClearGeneration
        self._isPulling = isPulling
    }
    
    @Binding var shouldClearChat: Bool
    @Binding var shouldClearGeneration: Bool
    @Binding var isPulling: Bool
    
    var body: some View {
        @Bindable var modelSettings = modelSettings
        Group {
#if os(macOS)
            MainNavigationView(
                selection: $selection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $modelSettings.modelListSortOrder,
                selectedFilterTag: $selectedFilterTag,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                columnVisibility: $columnVisibility,
                sortedModels: sortedModels
            )
#else
            MainTabView(
                selection: $selection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $modelSettings.modelListSortOrder,
                selectedFilterTag: $selectedFilterTag,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                sortedModels: sortedModels
            )
#endif
        }
        .environment(executor)
        .environment(chatSettings)
        .sheet(isPresented: $showingAddModelsSheet) {
            NavigationStack {
                AddModelsSheet(showingAddSheet: $showingAddModelsSheet, executor: executor)
                    .environment(appRefreshTrigger)
            }
#if os(iOS)
            .presentationBackground(Color(uiColor: .systemBackground))
#endif
#if os(visionOS)
            .frame(width: 500, height: 350)
            .presentationSizing(.fitted)
#endif
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationStack {
                ServerFormView(serverManager: serverManager, executor: executor, editingServer: nil)
                    .environment(appRefreshTrigger)
            }
#if os(iOS)
            .presentationBackground(Color(uiColor: .systemBackground))
#endif
#if os(visionOS)
            .frame(width: 500, height: 300)
            .presentationSizing(.fitted)
#endif
        }
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    Task {
                        await executor.deleteModel(modelName: model.name)
                    }
                }
                showingDeleteConfirmation = false
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = false
                modelToDelete = nil
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let model = modelToDelete { // 手動でアンラップ
                Text(String(localized: "Are you sure you want to delete the model \"\(model.name)\"?\nThis action cannot be undone.", comment: "モデル削除の確認メッセージ。"))
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "Are you sure you want to delete the selected model?\nThis action cannot be undone.", comment: "選択したモデル削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            updateSortedModels()
            handleOnAppear()
        }
        .onChange(of: selection) { _, newValue in
            Task { @MainActor in
                handleSelectionChange(newValue)
            }
        }
        .onChange(of: selectedModel) { _, newValue in handleModelSelectionChange(newValue) }
        .onChange(of: selectedServerForInspector) { _, newValue in handleServerSelectionChange(newValue) }
        .onChange(of: shouldClearChat) { _, newValue in handleClearChatChange(newValue) }
        .onChange(of: shouldClearGeneration) { _, newValue in handleClearGenerationChange(newValue) }
        .onChange(of: executor.models) { _, _ in updateSortedModels() }
        .onChange(of: modelSettings.modelListSortOrder) { _, _ in updateSortedModels() }
        .onChange(of: executor.isPulling) { _, newValue in isPulling = newValue }
        .onReceive(appRefreshTrigger.publisher) {
            Task { await performRefreshForCurrentSelection() }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleOnAppear() {
        selection = "server"
        updateSelectedServerForInspector()
        serverManager.inspectorSelection = selection
        serverManager.inspectorSelectedModelID = selectedModel
        serverManager.inspectorSelectedServer = selectedServerForInspector
    }
    
    private func handleSelectionChange(_ newSelection: String?) {
        serverManager.inspectorSelection = newSelection
        if newSelection == "server" {
            updateSelectedServerForInspector()
        }
        if newSelection == "settings" && showingInspector {
#if os(visionOS)
            withAnimation(.easeInOut(duration: 0.3)) {
                showingInspector = false
            }
#else
            showingInspector = false
#endif
        }
    }
    
    private func handleModelSelectionChange(_ newValue: OllamaModel.ID?) {
#if os(visionOS)
        withAnimation(.easeInOut(duration: 0.3)) {
            serverManager.inspectorSelectedModelID = newValue
        }
#else
        serverManager.inspectorSelectedModelID = newValue
#endif
    }
    
    private func handleServerSelectionChange(_ newServer: ServerInfo?) {
        serverManager.inspectorSelectedServer = newServer
        if newServer != nil {
            executor.resetInitialFetchFlag()
            Task {
                await executor.fetchOllamaModelsFromAPI()
            }
        }
    }
    
    private func handleClearChatChange(_ newValue: Bool) {
        if newValue {
            executor.clearChat()
            shouldClearChat = false
        }
    }
    
    private func handleClearGenerationChange(_ newValue: Bool) {
        if newValue {
            executor.clearImageGeneration()
            shouldClearGeneration = false
        }
    }
    
    private func updateSelectedServerForInspector() {
        guard let selectedID = serverManager.selectedServerID,
              let server = serverManager.servers.first(where: { $0.id == selectedID }) else {
            selectedServerForInspector = nil
            return
        }
        selectedServerForInspector = server
    }
    
    private func performRefreshForCurrentSelection() async {
        guard let currentSelection = selection else { return }
        
        switch currentSelection {
        case "server":
            try? await Task.sleep(nanoseconds: 100_000_000)
            // サーバー接続状態を再チェック
            for server in serverManager.servers {
                serverManager.updateServerConnectionStatus(serverID: server.id, status: .checking)
                Task {
                    let maxRetries = 3
                    var finalStatus: ServerConnectionStatus?
                    
                    for attempt in 1...maxRetries {
                        let status = await executor.checkAPIConnectivity(host: server.host)
                        finalStatus = status
                        
                        // 接続成功、またはリトライ対象外のエラー（サーバーからのメッセージ付き応答など）ならループを抜ける
                        if case .connected = status { break }
                        if case .errorWithMessage = status { break }
                        
                        // リトライ対象のエラーの場合
                        print("Attempt \(attempt) of \(maxRetries) failed for \(server.host). Status: \(status)")
                        if attempt < maxRetries {
                            print("Retrying in 0.5 seconds...")
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
                        }
                    }
                    
                    if let status = finalStatus {
                        await MainActor.run {
                            serverManager.updateServerConnectionStatus(serverID: server.id, status: status)
                        }
                    }
                }
            }
            
        case "models":
            // ダウンロード中はリフレッシュを実行しない
            guard !executor.isPulling else { return }
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            // モデルリストを再取得
            Task {
                executor.isPullingErrorHold = false
                executor.pullHasError = false
                executor.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
                executor.clearModelInfoCache()
                let previousSelection = selectedModel
                let selectedServerID = serverManager.selectedServerID
                selectedModel = nil
                
                if let sid = selectedServerID {
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: sid, status: .checking)
                    }
                }
                
                // 明示的なリフレッシュ（ボタン押しなど）の場合はフラグを無視して取得
                await executor.fetchOllamaModelsFromAPI()
                
                if let sid = selectedServerID, let host = serverManager.servers.first(where: { $0.id == sid })?.host {
                    let status = await executor.checkAPIConnectivity(host: host)
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: sid, status: status)
                    }
                }
                
                await MainActor.run {
                    serverManager.inspectorRefreshToken = UUID()
                    NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
                }
                if let prev = previousSelection, executor.models.contains(where: { $0.id == prev }) {
                    selectedModel = prev
                }
            }
            
        case "chat":
            // チャット画面でのリフレッシュ要請
            Task {
                executor.clearModelInfoCache()
                await executor.fetchOllamaModelsFromAPI()
            }
            
        case "image_generation":
            // 画像生成画面でのリフレッシュ要請
            Task {
                executor.clearModelInfoCache()
                await executor.fetchOllamaModelsFromAPI()
            }
            
        default:
            break
        }
    }
}

// MARK: - プレビュー用
#Preview {
    let previewServerManager = ServerManager()
    let previewExecutor = CommandExecutor(serverManager: previewServerManager)
    ContentView(serverManager: previewServerManager, executor: previewExecutor, selection: .constant("server"), showingInspector: .constant(false), showingAddModelsSheet: .constant(false), showingAddServerSheet: .constant(false), shouldClearChat: .constant(false), shouldClearGeneration: .constant(false), isPulling: .constant(false))
        .environment(RefreshTrigger())
}
