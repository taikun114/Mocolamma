import SwiftUI
import CompactSlider

// MARK: - Legacy iPhone Tab View (for older iOS versions)
struct LegacyIPhoneTabView: View {
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
