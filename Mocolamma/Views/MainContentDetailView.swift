import SwiftUI

// MARK: - メインコンテンツ詳細ヘルパービュー
struct MainContentDetailView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @ObservedObject var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    
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
                    showingInspector: $showingInspector,
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
