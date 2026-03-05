import SwiftUI
import CompactSlider

// MARK: - メインタブビュー（現代のOSバージョン用）
@available(macOS 15.0, iOS 18.0, *)
struct MainTabView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject var chatSettings: ChatSettings
    @EnvironmentObject var imageSettings: ImageGenerationSettings
    @Binding var selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    var executor: CommandExecutor
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServerForInspector: ServerInfo?
    @Binding var showingInspector: Bool
    @Binding var sortOrder: [KeyPathComparator<OllamaModel>]
    @Binding var selectedFilterTag: String?
    @Binding var showingAddModelsSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var modelToDelete: OllamaModel?
    var sortedModels: [OllamaModel]
    @State private var isInspectorSheetPresented = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ServerView(
                    serverManager: serverManager,
                    executor: executor,
                    onTogglePreview: toggleInspector,
                    selectedServerForInspector: $selectedServerForInspector
                )
            }
            .environmentObject(serverManager)
            .environment(executor)
            .tabItem { Label("Server", systemImage: "server.rack") }
            .tag("server")
            
            NavigationStack {
                ModelListView(
                    executor: executor,
                    selectedModel: $selectedModel,
                    sortOrder: $sortOrder,
                    showingAddSheet: $showingAddModelsSheet,
                    selectedFilterTag: $selectedFilterTag,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    modelToDelete: $modelToDelete,
                    isSelected: selection == "models",
                    onTogglePreview: toggleInspector
                )
            }
            .environmentObject(serverManager)
            .environment(executor)
            .tabItem { Label("Models", systemImage: "tray.full") }
            .tag("models")
            
            NavigationStack {
                ChatView(
                    showingInspector: $showingInspector,
                    onToggleInspector: toggleInspector
                )
            }
            .environmentObject(serverManager)
            .environment(executor)
            .tabItem { Label("Chat", systemImage: "message") }
            .tag("chat")
            
            NavigationStack {
                ImageGenerationView(
                    showingInspector: $showingInspector,
                    onToggleInspector: toggleInspector
                )
            }
            .environmentObject(serverManager)
            .environment(executor)
            .tabItem { Label("Image Generation", systemImage: "photo") }
            .tag("image_generation")
            
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag("settings")
        }
        .onChange(of: selection) { _, newSelection in
#if os(visionOS)
            withAnimation(.easeInOut(duration: 0.3)) {
                executor.previewImage = nil
                if newSelection == "settings" && showingInspector {
                    showingInspector = false
                }
            }
#else
            executor.previewImage = nil
            if newSelection == "settings" && showingInspector {
                showingInspector = false
            }
#endif
        }
        .tabViewStyle(.sidebarAdaptable)
#if !os(visionOS)
        .inspector(isPresented: (isiOSAppOnVision) ? .constant(false) : $showingInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 250, ideal: 250, max: 400)
        }
#endif
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
#if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
#if os(visionOS)
        .ornament(
            visibility: .automatic,
            attachmentAnchor: .scene(.trailing),
            contentAlignment: .leading
        ) {
            ZStack {
                if showingInspector {
                    // インスペクター全体のコンテナ（登場・退場アニメーション用）
                    ZStack {
                        // 内部コンテンツのコンテナ（コンテンツ切り替えフェード用）
                        // idをこのZStackに持たせることで、内部の inspectorContent がまるごと入れ替わるようにする
                        ZStack {
                            inspectorContent
                        }
                        .id("\(selection ?? "")-\(selectedModel ?? "")-\(selectedServerForInspector?.id.uuidString ?? "")")
                        .transition(.opacity)
                    }
                    .frame(width: 400, height: 600)
                    .glassBackgroundEffect()
                    .transition(.asymmetric(
                        insertion: .offset(x: -50).combined(with: .opacity),
                        removal: .offset(x: -50).combined(with: .opacity)
                    ))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selection)
            .animation(.easeInOut(duration: 0.3), value: selectedModel)
            .animation(.easeInOut(duration: 0.3), value: selectedServerForInspector)
            .animation(.easeInOut(duration: 0.3), value: showingInspector)
            .frame(width: 400, height: 600)
        }
#endif
    }
    
    private func toggleInspector() {
        if isNativeVisionOS {
            // visionOS用：インスペクタに表示する内容を同期
            serverManager.inspectorSelection = selection
            serverManager.inspectorSelectedServer = selectedServerForInspector
            
            // 選択中の画面に応じてモデルIDを同期
            if selection == "models" {
                serverManager.inspectorSelectedModelID = selectedModel
            } else if selection == "chat" {
                serverManager.inspectorSelectedModelID = chatSettings.selectedModelID
            } else if selection == "image_generation" {
                serverManager.inspectorSelectedModelID = imageSettings.selectedModelID
            }
            
            withAnimation(.easeOut(duration: 0.3)) {
                showingInspector.toggle()
            }
        } else if isiOSAppOnVision {
            isInspectorSheetPresented.toggle()
        } else {
            showingInspector.toggle()
        }
        
#if !os(macOS)
        // キーボードを非表示にする
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
    
    private var inspectorContent: some View {
        InspectorContentView(
            selection: selection,
            selectedModel: $selectedModel,
            sortedModels: sortedModels,
            selectedServerForInspector: selectedServerForInspector,
            serverManager: serverManager,
            showingInspector: $showingInspector,
            selectedFilterTag: $selectedFilterTag
        )
        .environmentObject(chatSettings)
        .environmentObject(imageSettings)
        .environment(executor)
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
