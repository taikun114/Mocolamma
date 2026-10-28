import SwiftUI
import CompactSlider

// MARK: - メインタブビュー（現代のOSバージョン用）
@available(macOS 15.0, iOS 18.0, *)
struct MainTabView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ChatSettings.self) var chatSettings
    @Environment(ImageGenerationSettings.self) var imageSettings
    @Binding var selection: String?
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
    var sortedModels: [OllamaModel]
    @State private var isInspectorSheetPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var generationPath: [String] = []
    @State private var tabBarPlacement: TabBarPlacement?

    private var usesCompactGeneration: Bool {
#if os(iOS)
        horizontalSizeClass == .compact && !isiOSAppOnVision
#else
        false
#endif
    }

    private var inspectorSelection: String? {
        selection == "generation" ? generationPath.last : selection
    }

    private var showsGenerationTab: Bool {
#if os(iOS)
        !isiOSAppOnVision && (usesCompactGeneration || tabBarPlacement != .sidebar || selection == "generation")
#else
        false
#endif
    }

    private var usesGenerationTab: Bool {
        usesCompactGeneration || (showsGenerationTab && tabBarPlacement == .topBar)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Server", systemImage: "server.rack", value: "server") {
                NavigationStack {
                    ServerView(
                        serverManager: serverManager,
                        executor: executor,
                        onTogglePreview: toggleInspector,
                        selectedServerForInspector: $selectedServerForInspector
                    )
                }
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
                .environment(serverManager)
                .environment(executor)
            }
            
            Tab("Models", systemImage: "tray.full", value: "models") {
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
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
                .environment(serverManager)
                .environment(executor)
            }
            
            Tab("Generation", systemImage: "sparkles", value: "generation") {
                NavigationStack(path: $generationPath) {
                    List {
                        NavigationLink(value: "chat") {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Chat")
                                        .fontWeight(.bold)
                                        .lineLimit(1)
                                    Text("Easily test your model's capabilities.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "message").foregroundStyle(.green)
                            }
                        }
                        NavigationLink(value: "image_generation") {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Image Generation")
                                        .fontWeight(.bold)
                                        .lineLimit(1)
                                    Text("Create a variety of images using image generation models.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "photo").foregroundStyle(.blue)
                            }
                        }
                    }
                    .navigationTitle("Generation")
                    .modifier(NavSubtitleIfAvailable(subtitle: serverManager.selectedServer.map { Text(verbatim: $0.name) } ?? Text("No Server Selected")))
                    .navigationDestination(for: String.self) { destination in
                        if destination == "chat" {
                            ChatView(showingInspector: $showingInspector, onToggleInspector: toggleInspector)
                        } else if destination == "image_generation" {
                            ImageGenerationView(showingInspector: $showingInspector, onToggleInspector: toggleInspector)
                        }
                    }
                }
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
                .environment(serverManager)
                .environment(executor)
            }
            .hidden(!showsGenerationTab)

            Tab("Chat", systemImage: "message", value: "chat") {
                NavigationStack {
                    ChatView(
                        showingInspector: $showingInspector,
                        onToggleInspector: toggleInspector
                    )
                }
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
                .environment(serverManager)
                .environment(executor)
            }
            .hidden(usesGenerationTab && selection != "chat")
            
            Tab("Image Generation", systemImage: "photo", value: "image_generation") {
                NavigationStack {
                    ImageGenerationView(
                        showingInspector: $showingInspector,
                        onToggleInspector: toggleInspector
                    )
                }
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
                .environment(serverManager)
                .environment(executor)
            }
            .hidden(usesGenerationTab && selection != "image_generation")
            
            Tab("Settings", systemImage: "gear", value: "settings") {
                NavigationStack {
                    SettingsView()
                }
                .background(TabBarPlacementObserver(placement: $tabBarPlacement))
            }
        }
        .onChange(of: usesGenerationTab, initial: true) { _, grouped in
            if grouped, let selection, selection == "chat" || selection == "image_generation" {
                generationPath = [selection]
                self.selection = "generation"
            }
        }
        .onChange(of: tabBarPlacement, initial: true) { _, placement in
            if placement == .sidebar, !usesCompactGeneration, selection == "generation" {
                selection = generationPath.last ?? "chat"
            }
        }
        .onChange(of: usesCompactGeneration) { _, compact in
            if !compact, tabBarPlacement == .sidebar, selection == "generation" {
                selection = generationPath.last ?? "chat"
            }
        }
        .onChange(of: selection) { _, newSelection in
            // タブが切り替えられたときに、重い状態更新を非同期化してメインスレッドの占有を避け、アニメーションをスムーズにする
            Task { @MainActor in
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
        }
        .tabViewStyle(.sidebarAdaptable)
#if os(iOS)
        .defaultTabBarPlacementIfAvailable(.sidebar)
#endif
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
            selection: inspectorSelection,
            selectedModel: $selectedModel,
            sortedModels: sortedModels,
            selectedServerForInspector: selectedServerForInspector,
            serverManager: serverManager,
            showingInspector: $showingInspector,
            selectedFilterTag: $selectedFilterTag
        )
        .environment(chatSettings)
        .environment(imageSettings)
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

private struct TabBarPlacementObserver: View {
    @Environment(\.tabBarPlacement) private var currentPlacement
    @Binding var placement: TabBarPlacement?

    var body: some View {
#if os(iOS)
        if #available(iOS 27.0, *) {
            AdaptiveTabBarPlacementObserver(placement: $placement)
        } else {
            placementObserver
        }
#else
        placementObserver
#endif
    }

    private var placementObserver: some View {
        Color.clear
            .onChange(of: currentPlacement, initial: true) { _, newValue in
                if let newValue {
                    placement = newValue
                }
            }
    }
}

#if os(iOS)
@available(iOS 27.0, *)
private struct AdaptiveTabBarPlacementObserver: View {
    @Environment(\.tabBarPlacement) private var currentPlacement
    @Environment(\.isTabViewSidebarAvailable) private var isSidebarAvailable
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var placement: TabBarPlacement?

    private var resolvedPlacement: TabBarPlacement? {
        // サイドバー優先時にbottomBarが報告される環境では、利用可否と表示領域で補正する。
        isSidebarAvailable && horizontalSizeClass == .regular && currentPlacement == .bottomBar ? .sidebar : currentPlacement
    }

    var body: some View {
        Color.clear
            .onChange(of: resolvedPlacement, initial: true) { _, newValue in
                if let newValue {
#if DEBUG
                    print("Adaptive tab placement: \(newValue), sidebar available: \(isSidebarAvailable)")
#endif
                    placement = newValue
                }
            }
    }
}
#endif

#if os(iOS)
// MARK: - View拡張

extension View {
    /// 利用可能な場合にタブバーのデフォルト配置を設定
    @ViewBuilder
    func defaultTabBarPlacementIfAvailable(_ placement: AdaptableTabBarPlacement) -> some View {
        if #available(iOS 27.0, *) {
            self.defaultTabBarPlacement(placement)
        } else {
            self
        }
    }
}
#endif
