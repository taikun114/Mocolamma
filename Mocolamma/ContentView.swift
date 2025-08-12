import SwiftUI
import Foundation // Task { @MainActor in } を使用するため
import CompactSlider
import Combine

// MARK: - コンテンツビュー

/// アプリのメインウィンドウを構成するSwiftUIビューです。
/// プラットフォームに応じて、NavigationSplitViewまたはTabViewを使用してUIを構築します。
struct ContentView: View {
    // ServerManagerのインスタンスをAppStateに保持し、ライフサイクル全体で利用可能にする
    @ObservedObject var serverManager: ServerManager
    // CommandExecutorはServerManagerに依存するため、後から初期化
    @StateObject var executor: CommandExecutor

    @State private var selectedModel: OllamaModel.ID? // 選択されたモデルのID
    @State private var selectedChatModelID: OllamaModel.ID? // チャットで選択されたモデルのID
    // サイドバー/タブの選択状態をAppレベルから受け取ります
    @Binding var selection: String?
    
    // NavigationSplitViewのサイドバーの表示状態を制御するState変数
    @State private var columnVisibility: NavigationSplitViewVisibility = .all // デフォルトで全パネル表示

    // Inspector（プレビューパネル）の表示/非表示を制御するState変数を@Bindingに変更
    @Binding var showingInspector: Bool
    @State private var isChatStreamingEnabled: Bool = true // ChatViewのストリーム設定
    @State private var useCustomChatSettings: Bool = false // カスタムチャット設定の有効化
    @State private var chatTemperature: Double = 0.8 // Temperatureの初期値
    @State private var isTemperatureEnabled: Bool = false // 新しく追加
    @State private var isContextWindowEnabled: Bool = false // ここを追加
    @State private var contextWindowValue: Double = 2048.0 // ここを2048.0に変更
    @State private var isSystemPromptEnabled: Bool = false
    @State private var systemPrompt: String = ""
    @State private var thinkingOption: ThinkingOption = .none

    // モデル追加シートの表示/非表示を制御します
    @Binding var showingAddModelsSheet: Bool
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

    // MARK: - Server Inspector related states
    @State private var selectedServerForInspector: ServerInfo? // Inspectorに表示するサーバー情報
    @EnvironmentObject var appRefreshTrigger: RefreshTrigger
    
    // リフレッシュトリガーを受け取る
    
    
    // ContentViewの初期化子を更新
    init(serverManager: ServerManager, selection: Binding<String?>, showingInspector: Binding<Bool>, showingAddModelsSheet: Binding<Bool>) {
        self.serverManager = serverManager
        _executor = StateObject(wrappedValue: CommandExecutor(serverManager: serverManager))
        self._selection = selection
        self._showingInspector = showingInspector
        self._showingAddModelsSheet = showingAddModelsSheet
    }

    var body: some View {
        Group {
            #if os(macOS)
            MainNavigationView(
                sidebarSelection: $selection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                columnVisibility: $columnVisibility,
                sortedModels: sortedModels,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
            #elseif os(iOS)
            if #available(iOS 18.0, *) {
                MainTabView(
                    selection: $selection,
                    selectedModel: $selectedModel,
                    selectedChatModelID: $selectedChatModelID,
                    executor: executor,
                    serverManager: serverManager,
                    selectedServerForInspector: $selectedServerForInspector,
                    showingInspector: $showingInspector,
                    sortOrder: $sortOrder,
                    showingAddModelsSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    sortedModels: sortedModels,
                    isChatStreamingEnabled: $isChatStreamingEnabled,
                    useCustomChatSettings: $useCustomChatSettings,
                    chatTemperature: $chatTemperature,
                    isTemperatureEnabled: $isTemperatureEnabled,
                    isContextWindowEnabled: $isContextWindowEnabled,
                    contextWindowValue: $contextWindowValue,
                    isSystemPromptEnabled: $isSystemPromptEnabled,
                    systemPrompt: $systemPrompt,
                    thinkingOption: $thinkingOption
                )
            } else {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    LegacyIPhoneTabView(
                        selection: $selection,
                        selectedModel: $selectedModel,
                        selectedChatModelID: $selectedChatModelID,
                        executor: executor,
                        serverManager: serverManager,
                        selectedServerForInspector: $selectedServerForInspector,
                        showingInspector: $showingInspector,
                        sortOrder: $sortOrder,
                        showingAddModelsSheet: $showingAddModelsSheet,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        modelToDelete: $modelToDelete,
                        sortedModels: sortedModels,
                        isChatStreamingEnabled: $isChatStreamingEnabled,
                        useCustomChatSettings: $useCustomChatSettings,
                        chatTemperature: $chatTemperature,
                        isTemperatureEnabled: $isTemperatureEnabled,
                        isContextWindowEnabled: $isContextWindowEnabled,
                        contextWindowValue: $contextWindowValue,
                        isSystemPromptEnabled: $isSystemPromptEnabled,
                        systemPrompt: $systemPrompt,
                        thinkingOption: $thinkingOption
                    )
                } else {
                    MainNavigationView(
                        sidebarSelection: $selection,
                        selectedModel: $selectedModel,
                        selectedChatModelID: $selectedChatModelID,
                        executor: executor,
                        serverManager: serverManager,
                        selectedServerForInspector: $selectedServerForInspector,
                        showingInspector: $showingInspector,
                        sortOrder: $sortOrder,
                        showingAddModelsSheet: $showingAddModelsSheet,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        modelToDelete: $modelToDelete,
                        columnVisibility: $columnVisibility,
                        sortedModels: sortedModels,
                        isChatStreamingEnabled: $isChatStreamingEnabled,
                        useCustomChatSettings: $useCustomChatSettings,
                        chatTemperature: $chatTemperature,
                        isTemperatureEnabled: $isTemperatureEnabled,
                        isContextWindowEnabled: $isContextWindowEnabled,
                        contextWindowValue: $contextWindowValue,
                        isSystemPromptEnabled: $isSystemPromptEnabled,
                        systemPrompt: $systemPrompt,
                        thinkingOption: $thinkingOption
                    )
                }
            }
            #else
            MainNavigationView(
                sidebarSelection: $selection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                columnVisibility: $columnVisibility,
                sortedModels: sortedModels,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
            #endif
        }
        .environmentObject(executor)
        .sheet(isPresented: $showingAddModelsSheet) {
            NavigationStack {
                AddModelsSheet(showingAddSheet: $showingAddModelsSheet, executor: executor)
                    .environmentObject(appRefreshTrigger)
            }
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
            .keyboardShortcut(.defaultAction) // Added here
        } message: {
            if let model = modelToDelete { // 手動でアンラップ
                Text(String(localized: "Are you sure you want to delete the model \"\(model.name)\"?\nThis action cannot be undone.", comment: "モデル削除の確認メッセージ。"))
            } else {
                // modelToDeleteがnilの場合のフォールバックメッセージ
                Text(String(localized: "Are you sure you want to delete the selected model?\nThis action cannot be undone.", comment: "選択したモデル削除の確認メッセージ（フォールバック）。"))
            }
        }
        .onAppear {
            selection = "server"
        }
        .onChange(of: selection) { oldSelection, newSelection in
            if newSelection == "server" {
                updateSelectedServerForInspector()
            }
            if newSelection == "settings" && showingInspector {
                showingInspector = false
            }
        }
        .onChange(of: serverManager.selectedServerID) { _, _ in
            // API通信用の選択IDが変更されても、Inspectorの表示はServerViewのlistSelectionに任せる
        }
        .onChange(of: selectedServerForInspector) { oldServer, newServer in
            if newServer != nil {
                if selection == "server" {
                    appRefreshTrigger.send()
                }
            }
        }
        .onReceive(appRefreshTrigger.publisher) {
            Task { await performRefreshForCurrentSelection() }
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
                serverManager.updateServerConnectionStatus(serverID: server.id, status: nil)
                Task {
                    let isConnected = await executor.checkAPIConnectivity(host: server.host)
                    await MainActor.run {
                        serverManager.updateServerConnectionStatus(serverID: server.id, status: isConnected)
                    }
                }
            }
            
        case "models":
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
                await executor.fetchOllamaModelsFromAPI()
                if let sid = selectedServerID {
                    serverManager.updateServerConnectionStatus(serverID: sid, status: nil)
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
            // チャットではモデルリストを再取得
            Task {
                executor.clearModelInfoCache()
                await executor.fetchOllamaModelsFromAPI()
            }
            
        default:
            break
        }
    }
}

// MARK: - Main Tab View (for modern OS versions)
@available(macOS 15.0, iOS 18.0, *)
private struct MainTabView: View {
    @Binding var selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID? // 新しく追加
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    let sortedModels: [OllamaModel]
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: { showingInspector.toggle() },
                    selectedServerForInspector: $selectedServerForInspector
                )
            }
            .tabItem { Label("Server", systemImage: "server.rack") }
            .tag("server")

            NavigationStack {
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    onTogglePreview: { showingInspector.toggle() }
                )
            }
            .environmentObject(serverManager)
            .environmentObject(executor)
            .tabItem { Label("Models", systemImage: "tray.full") }
            .tag("models")

            NavigationStack {
                ChatView(
                    selectedModelID: $selectedChatModelID, // ここを変更
                    isStreamingEnabled: $isChatStreamingEnabled,
                    showingInspector: $showingInspector,
                    useCustomChatSettings: $useCustomChatSettings,
                    chatTemperature: $chatTemperature,
                    isTemperatureEnabled: $isTemperatureEnabled,
                    isContextWindowEnabled: $isContextWindowEnabled,
                    contextWindowValue: $contextWindowValue,
                    isSystemPromptEnabled: $isSystemPromptEnabled,
                    systemPrompt: $systemPrompt,
                    thinkingOption: $thinkingOption
                )
            }
            .environmentObject(serverManager)
            .environmentObject(executor)
            .tabItem { Label("Chat", systemImage: "message") }
            .tag("chat")

            #if os(iOS)
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag("settings")
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        .inspector(isPresented: $showingInspector) {
            InspectorContentView(
                selection: selection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID, // 新しく追加
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector,
                serverManager: serverManager,
                showingInspector: $showingInspector,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
            .inspectorColumnWidth(min: 250, ideal: 250, max: 400)
        }
    }
}

// MARK: - Legacy iPhone Tab View (for older iOS versions)
private struct LegacyIPhoneTabView: View {
    @Binding var selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID?
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    let sortedModels: [OllamaModel]
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: { showingInspector.toggle() },
                    selectedServerForInspector: $selectedServerForInspector
                )
            }
            .tabItem { Label("Server", systemImage: "server.rack") }
            .tag("server")

            NavigationStack {
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    onTogglePreview: { showingInspector.toggle() }
                )
            }
            .environmentObject(serverManager)
            .environmentObject(executor)
            .tabItem { Label("Models", systemImage: "tray.full") }
            .tag("models")

            NavigationStack {
                ChatView(
                    selectedModelID: $selectedChatModelID,
                    isStreamingEnabled: $isChatStreamingEnabled,
                    showingInspector: $showingInspector,
                    useCustomChatSettings: $useCustomChatSettings,
                    chatTemperature: $chatTemperature,
                    isTemperatureEnabled: $isTemperatureEnabled,
                    isContextWindowEnabled: $isContextWindowEnabled,
                    contextWindowValue: $contextWindowValue,
                    isSystemPromptEnabled: $isSystemPromptEnabled,
                    systemPrompt: $systemPrompt,
                    thinkingOption: $thinkingOption
                )
            }
            .environmentObject(serverManager)
            .environmentObject(executor)
            .tabItem { Label("Chat", systemImage: "message") }
            .tag("chat")

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag("settings")
        }
        .inspector(isPresented: $showingInspector) {
            InspectorContentView(
                selection: selection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID,
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector,
                serverManager: serverManager,
                showingInspector: $showingInspector,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
            .inspectorColumnWidth(min: 250, ideal: 250, max: 400)
        }
    }
}



// MARK: - Main Navigation View Helper (for older OS versions)
private struct MainNavigationView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID? // 新しく追加
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sortedModels: [OllamaModel]
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $sidebarSelection) {
                Label("Server", systemImage: "server.rack").tag("server")
                Label("Models", systemImage: "tray.full").tag("models")
                Label("Chat", systemImage: "message").tag("chat")
                #if os(iOS)
                Label("Settings", systemImage: "gear").tag("settings")
                #endif
            }
            .navigationTitle("Menu")
            .navigationSplitViewColumnWidth(min: 150, ideal: 300, max: 500)
        } detail: {
            MainContentDetailView(
                sidebarSelection: $sidebarSelection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID, // 新しく追加
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
        }
        .inspector(isPresented: $showingInspector) {
            InspectorContentView(
                selection: sidebarSelection,
                selectedModel: $selectedModel,
                selectedChatModelID: $selectedChatModelID, // 新しく追加
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector,
                serverManager: serverManager,
                showingInspector: $showingInspector,
                isChatStreamingEnabled: $isChatStreamingEnabled,
                useCustomChatSettings: $useCustomChatSettings,
                chatTemperature: $chatTemperature,
                isTemperatureEnabled: $isTemperatureEnabled,
                isContextWindowEnabled: $isContextWindowEnabled,
                contextWindowValue: $contextWindowValue,
                isSystemPromptEnabled: $isSystemPromptEnabled,
                systemPrompt: $systemPrompt,
                thinkingOption: $thinkingOption
            )
            .inspectorColumnWidth(min: 250, ideal: 250, max: 400)
        }
    }
}

// MARK: - Inspector Content Helper View
private struct InspectorContentView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID? // 新しく追加
    let sortedModels: [OllamaModel]
    let selectedServerForInspector: ServerInfo?
    @ObservedObject var serverManager: ServerManager
    @Binding var showingInspector: Bool
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    
    @State private var modelInfo: [String: JSONValue]?
    @State private var licenseBody: String?
    @State private var licenseLink: String?
    @State private var isLoadingInfo: Bool = false
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        Group {
            if selection == "models" {
                if let selectedModelID = selectedModel,
                   let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                    ModelInspectorDetailView(
                        model: model,
                        modelInfo: modelInfo,
                        isLoading: isLoadingInfo,
                        fetchedCapabilities: commandExecutor.selectedModelCapabilities,
                        licenseBody: licenseBody,
                        licenseLink: licenseLink
                    )
                    .id(model.id)
                } else {
                    Text("Select a model to see the details.") // モデルが選択されていない場合
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .id("model_selection_placeholder")
                        .padding()
                }
            } else if selection == "server" {
                if let server = selectedServerForInspector {
                    ServerInspectorDetailView(
                        server: server,
                        connectionStatus: serverManager.serverConnectionStatuses[server.id] ?? nil
                    )
                    .id(UUID())
                } else {
                    Text("Select a server to see the details.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .id("server_selection_placeholder")
                        .padding()
                }
            } else if selection == "chat" {
                Form {
                    Section("Chat Settings") {
                        Toggle("Stream Response", isOn: $isChatStreamingEnabled)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Thinking", selection: $thinkingOption) {
                                ForEach(ThinkingOption.allCases) { option in
                                    Text(option.localizedName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(!(commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false))
                            .onChange(of: commandExecutor.selectedModelCapabilities) { _, caps in
                                let hasThinking = caps?.contains("thinking") ?? false
                                if !hasThinking { thinkingOption = .none }
                            }
                            Text("Specifies whether to perform inference when using a reasoning model.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Toggle(isOn: $isSystemPromptEnabled) {
                                Text("System Prompt")
                            }
                            TextEditor(text: $systemPrompt)
                                .frame(height: 100)
                                .disabled(!isSystemPromptEnabled)
                                .foregroundColor(isSystemPromptEnabled ? .primary : .secondary)
                                .scrollContentBackground(.hidden)
                                .background(isSystemPromptEnabled ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Section("Custom Settings") {
                        Toggle("Enable Custom Settings", isOn: $useCustomChatSettings)
                        
                        VStack {
                            Toggle(isOn: $isTemperatureEnabled) {
                                Text("Temperature")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $chatTemperature, in: 0.0...2.0, step: 0.1)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text(String(format: "%.1f", chatTemperature))
                                    .font(.body.monospaced())
                            }
                            .disabled(!isTemperatureEnabled)
                            .foregroundColor(isTemperatureEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!useCustomChatSettings)
                        .foregroundColor(useCustomChatSettings ? .primary : .secondary)

                        VStack {
                            Toggle(isOn: $isContextWindowEnabled) {
                                Text("Context Window")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $contextWindowValue, in: 512...Double(commandExecutor.selectedModelContextLength ?? 4096), step: 128.0)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text("\(Int(contextWindowValue))")
                                    .font(.body.monospaced())
                            }
                            .disabled(!isContextWindowEnabled)
                            .foregroundColor(isContextWindowEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!useCustomChatSettings)
                        .foregroundColor(useCustomChatSettings ? .primary : .secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
            } else {
                Text("Nothing to display.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("nothing_to_display_placeholder")
                    .padding()
            }
        }
        .onChange(of: selectedModel) { _, newID in
            modelInfo = nil
            isLoadingInfo = true
            licenseBody = nil
            
            guard let newID = newID,
                  let model = sortedModels.first(where: { $0.id == newID }) else {
                isLoadingInfo = false
                return
            }
            
            Task {
                let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
                if selectedModel == newID {
                    await MainActor.run {
                        self.modelInfo = fetchedResponse?.model_info
                        self.licenseBody = fetchedResponse?.license
                        self.licenseLink = fetchedResponse?.model_info?["general.license.link"]?.stringValue
                        self.isLoadingInfo = false
                        let hasThinkingCapability = self.commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false
                        if !hasThinkingCapability {
                            self.thinkingOption = .none
                        }
                    }
                }
            }
        }
        .onChange(of: selectedChatModelID) { _, newID in // 新しく追加
            modelInfo = nil
            isLoadingInfo = true
            licenseBody = nil
            
            guard let newID = newID,
                  let model = sortedModels.first(where: { $0.id == newID }) else {
                isLoadingInfo = false
                return
            }
            
            Task {
                let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
                if selectedChatModelID == newID { // ここを変更
                    await MainActor.run {
                        self.modelInfo = fetchedResponse?.model_info
                        self.licenseBody = fetchedResponse?.license
                        self.licenseLink = fetchedResponse?.model_info?["general.license.link"]?.stringValue
                        self.isLoadingInfo = false
                        let hasThinkingCapability = self.commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false
                        if !hasThinkingCapability {
                            self.thinkingOption = .none
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .toolbar {
            Spacer()
            Button {
                showingInspector.toggle()
            } label: {
                Label(showingInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .help("Toggle Inspector")
        }
        #endif
    }
}

// MARK: - Model Inspector Detail View Helper
private struct ModelInspectorDetailView: View {
    let model: OllamaModel
    let modelInfo: [String: JSONValue]?
    let isLoading: Bool
    let fetchedCapabilities: [String]?
    let licenseBody: String?
    let licenseLink: String?

    var body: some View {
        ModelInspectorView(
            model: model,
            modelInfo: modelInfo,
            isLoading: isLoading,
            fetchedCapabilities: fetchedCapabilities,
            licenseBody: licenseBody,
            licenseLink: licenseLink
        )
    }
}

// MARK: - Server Inspector Detail View Helper
private struct ServerInspectorDetailView: View {
    let server: ServerInfo
    let connectionStatus: Bool?

    var body: some View {
        ServerInspectorView(
            server: server,
            connectionStatus: connectionStatus
        )
    }
}

// MARK: - Main Content Detail Helper View
private struct MainContentDetailView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID? // 新しく追加
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        Group {
            if sidebarSelection == "models" {
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddModelsSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    onTogglePreview: { showingInspector.toggle() }
                )
                .environmentObject(serverManager)
            } else if sidebarSelection == "server" {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: { showingInspector.toggle() },
                    selectedServerForInspector: $selectedServerForInspector
                )
            } else if sidebarSelection == "chat" {
                ChatView(
                    selectedModelID: $selectedChatModelID, // ここを変更
                    isStreamingEnabled: $isChatStreamingEnabled,
                    showingInspector: $showingInspector,
                    useCustomChatSettings: $useCustomChatSettings,
                    chatTemperature: $chatTemperature,
                    isTemperatureEnabled: $isTemperatureEnabled,
                    isContextWindowEnabled: $isContextWindowEnabled,
                    contextWindowValue: $contextWindowValue,
                    isSystemPromptEnabled: $isSystemPromptEnabled,
                    systemPrompt: $systemPrompt,
                    thinkingOption: $thinkingOption
                )
                .environmentObject(executor)
                .environmentObject(serverManager)
            } else if sidebarSelection == "settings" {
                SettingsView()
            } else {
                Text("Select a menu.")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - プレビュー用
#Preview {
    let previewServerManager = ServerManager()
    ContentView(serverManager: previewServerManager, selection: .constant("server"), showingInspector: .constant(false), showingAddModelsSheet: .constant(false))
        .environmentObject(RefreshTrigger())
}
