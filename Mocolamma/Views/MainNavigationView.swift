import SwiftUI
import CompactSlider

// MARK: - メインナビゲーションビューヘルパー（古いOSバージョン用）
struct MainNavigationView: View {
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
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sortedModels: [OllamaModel]

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
            .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 250) // サイドバーの幅
        } detail: {
            MainContentDetailView(
                sidebarSelection: $sidebarSelection,
                selectedModel: $selectedModel,
                executor: executor,
                serverManager: serverManager,
                selectedServerForInspector: $selectedServerForInspector,
                showingInspector: $showingInspector,
                sortOrder: $sortOrder,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                modelToDelete: $modelToDelete
            )
        }
        .inspector(isPresented: $showingInspector) {
            InspectorContentView(
                selection: sidebarSelection,
                selectedModel: $selectedModel,
                sortedModels: sortedModels,
                selectedServerForInspector: selectedServerForInspector,
                serverManager: serverManager,
                showingInspector: $showingInspector
            )
            .inspectorColumnWidth(min: 250, ideal: 250, max: 300) // インスペクタの幅
        }
    }
}
