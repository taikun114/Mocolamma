import SwiftUI
import CompactSlider

// MARK: - Main Navigation View Helper (for older OS versions)
struct MainNavigationView: View {
    @Binding var sidebarSelection: String?
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
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            MainContentDetailView(
                sidebarSelection: $sidebarSelection,
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
