import SwiftUI
import CompactSlider

// MARK: - Main Tab View (for modern OS versions)
@available(macOS 15.0, iOS 18.0, *)
struct MainTabView: View {
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
    
    @State private var isInspectorSheetPresented = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: { toggleInspector() },
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
                    isSelected: selection == "models",
                    onTogglePreview: { toggleInspector() }
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
                    thinkingOption: $thinkingOption,
                    onToggleInspector: toggleInspector
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
        .inspector(isPresented: isiOSAppOnVision ? .constant(false) : $showingInspector) {
            inspectorContent
        }
        .sheet(isPresented: $isInspectorSheetPresented) {
            NavigationStack {
                inspectorContent
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { isInspectorSheetPresented = false }) {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                    .navigationTitle(inspectorTitle)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
    }

    private func toggleInspector() {
        if isiOSAppOnVision {
            isInspectorSheetPresented.toggle()
        } else {
            showingInspector.toggle()
        }
    }

    private var inspectorContent: some View {
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

    private var inspectorTitle: String {
        switch selection {
        case "server":
            return selectedServerForInspector?.name ?? String(localized: "Server Details")
        case "models":
            if let modelName = sortedModels.first(where: { $0.id == selectedModel })?.name {
                return modelName
            } else {
                return String(localized: "Model Details")
            }
        case "chat":
            return ""
        default:
            return ""
        }
    }
}
