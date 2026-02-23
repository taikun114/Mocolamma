import SwiftUI

// MARK: - メインナビゲーションビュー（macOS専用）
struct MainNavigationView: View {
    @Binding var selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sortedModels: [OllamaModel]
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Label("Server", systemImage: "server.rack").tag("server")
                Label("Models", systemImage: "tray.full").tag("models")
                Label("Chat", systemImage: "message").tag("chat")
                Label("Image Generation", systemImage: "photo").tag("image_generation")
            }
            .navigationTitle("Menu")
            .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 250) // サイドバーの幅を固定
        } detail: {
            MainContentDetailView(
                sidebarSelection: $selection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete,
                sortedModels: sortedModels
            )
        }
        .inspector(isPresented: $showingInspector) {
            InspectorContentView(
                selection: selection,
                selectedModel: $selectedModel,
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector,
                serverManager: serverManager,
                showingInspector: $showingInspector
            )
            .inspectorColumnWidth(min: 250, ideal: 250, max: 300)
        }
    }
}
