import SwiftUI

// MARK: - Main Content Detail Helper View
struct MainContentDetailView: View {
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
                    isSelected: sidebarSelection == "models",
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
                    thinkingOption: $thinkingOption,
                    onToggleInspector: { showingInspector.toggle() }
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
