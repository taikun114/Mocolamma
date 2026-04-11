import SwiftUI

struct MainContentDetailView: View {
    @Binding var sidebarSelection: String?
    @Binding var selectedModel: OllamaModel.ID?
    var executor: CommandExecutor
    var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var selectedFilterTag: String?
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    let sortedModels: [OllamaModel]

    var body: some View {
        Group {
            if sidebarSelection == "models" {
                NavigationStack {
                    ModelListView(
                        executor: executor,
                        selectedModel: $selectedModel,
                        sortOrder: $sortOrder,
                        showingAddSheet: $showingAddModelsSheet,
                        selectedFilterTag: $selectedFilterTag,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        modelToDelete: $modelToDelete,
                        isSelected: sidebarSelection == "models",
                        onTogglePreview: { showingInspector.toggle() }
                    )
                }
                .environment(serverManager)
                .environment(executor)
            } else if sidebarSelection == "server" {
                NavigationStack {
                    ServerView(
                        serverManager: serverManager,
                        executor: executor,
                        onTogglePreview: { showingInspector.toggle() },
                        selectedServerForInspector: $selectedServerForInspector
                    )
                }
                .environment(executor)
            } else if sidebarSelection == "chat" {
                NavigationStack {
                    ChatView(
                        showingInspector: $showingInspector,
                        onToggleInspector: { showingInspector.toggle() }
                    )
                }
                .environment(serverManager)
                .environment(executor)
            } else if sidebarSelection == "image_generation" {
                NavigationStack {
                    ImageGenerationView(
                        showingInspector: $showingInspector,
                        onToggleInspector: { showingInspector.toggle() }
                    )
                }
                .environment(serverManager)
                .environment(executor)
            } else {
                ZStack {
                    ScrollView {
                        Color.clear.frame(height: 1)
                    }
                    .modifier(SoftEdgeIfAvailable(enabled: true))
                    
                    ContentUnavailableView {
                        Label("Select a Menu", systemImage: "sidebar.leading")
                    } description: {
                        Text("Please select an item from the sidebar.")
                    }
                }
            }
        }
    }
}
