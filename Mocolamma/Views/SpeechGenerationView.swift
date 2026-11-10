import SwiftUI
import Textual

struct SpeechGenerationView: View {
    @Environment(CommandExecutor.self) var executor
    @Environment(ServerManager.self) var serverManager
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    @Environment(SpeechSession.self) var speech
    private var modelSettings = ModelSettingsManager.shared
    @State private var selectionCoordinator = TextSelectionCoordinator()

    @State private var showingClearConfirm: Bool = false
    @State private var inputAreaHeight: CGFloat = 0
    @State private var isNearBottom: Bool = true
    @State private var scrollToBottomTrigger: Int = 0
    @State private var scrollToMessageIDTrigger: UUID? = nil

    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void

    init(showingInspector: Binding<Bool>, onToggleInspector: @escaping () -> Void) {
        self._showingInspector = showingInspector
        self.onToggleInspector = onToggleInspector
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var currentSelectedModel: OllamaModel? {
        if let id = speech.selectedModelID {
            return executor.models.first(where: { $0.id == id })
        }
        return nil
    }

    private var subtitle: Text {
        if let serverName = serverManager.selectedServer?.name {
            return Text(LocalizedStringKey(serverName))
        } else {
            return Text("No Server Selected")
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var speech = speech
        ZStack {
            if serverManager.selectedServer == nil {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "server.rack",
                    description: Text("Please select a server in the Server tab.")
                )
            } else if executor.apiConnectionError {
                ContentUnavailableView(
                    "Connection Failed",
                    systemImage: "network.slash",
                    description: Text(LocalizedStringKey(executor.specificConnectionErrorMessage ?? "Failed to connect to the Ollama API. Please check your network connection or server settings."))
                )
            } else {
                ChatMessagesView(
                    messages: $speech.messages,
                    onRetry: retrySpeech,
                    isOverallStreaming: Binding(get: { speech.isGenerating }, set: { _ in }),
                    isNearBottom: $isNearBottom,
                    scrollToBottomTrigger: $scrollToBottomTrigger,
                    scrollToMessageIDTrigger: $scrollToMessageIDTrigger,
                    isModelSelected: speech.selectedModelID != nil,
                    allowsAttachments: false,
                    bottomInset: inputAreaHeight,
                    emptyStateTitle: "Speech Generation",
                    emptyStateDescription: "Here you can generate speech using models that support speech generation.",
                    emptyStateImage: ModelCapabilityTag("speech").iconName
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var speechInputArea: some View {
        @Bindable var speech = speech
        ChatInputView(
            inputText: $speech.input,
            selectedImages: .constant([]),
            isStreaming: Binding(get: { speech.isGenerating }, set: { _ in }),
            showingInspector: $showingInspector,
            allowsAttachments: false,
            placeholder: String(localized: "Enter text to read aloud..."),
            selectedModel: currentSelectedModel
        ) {
            generateSpeech()
        } stopMessage: {
            speech.cancel()
        }
#if os(macOS)
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, 16)
#elseif !os(visionOS)
        .padding()
#endif
#if os(visionOS)
        .onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.height + 32) / 2
        } action: { newValue in
            inputAreaHeight = newValue
        }
#endif
    }

    @ViewBuilder
    private var scrollToBottomArea: some View {
        ScrollToBottomButton(
            isNearBottom: isNearBottom,
            messagesEmpty: speech.messages.isEmpty,
            scrollToBottomTrigger: $scrollToBottomTrigger
        )
        .animation(.spring(duration: 0.3), value: isNearBottom)
        .animation(.spring(duration: 0.3), value: speech.messages.isEmpty)
    }

    var body: some View {
        Group {
#if os(visionOS)
            ZStack(alignment: .bottom) {
                if #available(visionOS 26.0, *) {
                    content
                        .safeAreaBar(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                } else {
                    content
                        .safeAreaInset(edge: .bottom) {
                            if inputAreaHeight > 0 {
                                Color.clear
                                    .frame(height: inputAreaHeight)
                            }
                        }
                }

                ZStack(alignment: .bottom) {
                    ScrollToBottomButton(isNearBottom: isNearBottom, messagesEmpty: speech.messages.isEmpty, scrollToBottomTrigger: $scrollToBottomTrigger)
                        .padding(.bottom, inputAreaHeight + 8)
                }
                .animation(.spring(duration: 0.3), value: isNearBottom)
                .animation(.spring(duration: 0.3), value: speech.messages.isEmpty)
            }
            .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
                speechInputArea
                    .frame(width: 600)
                    .padding(16)
                    .glassBackgroundEffect()
            }
#elseif os(iOS)
            if #available(iOS 26.0, *) {
                content
                    .overlay(alignment: .bottom) {
                        scrollToBottomArea
                    }
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        speechInputArea
                    }
            } else {
                content
                    .overlay(alignment: .bottom) {
                        scrollToBottomArea
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        speechInputArea
                            .if(horizontalSizeClass != .compact) { view in
                                view.ignoresSafeArea(.container, edges: [.bottom])
                            }
                    }
            }
#else
            if #available(macOS 26.0, *) {
                content
                    .overlay(alignment: .bottom) {
                        scrollToBottomArea
                    }
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        speechInputArea
                    }
            } else {
                content
                    .overlay(alignment: .bottom) {
                        scrollToBottomArea
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        speechInputArea
                    }
            }
#endif
        }
#if !os(macOS)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            selectionCoordinator.deselectAll()
        }
#endif
        .environment(selectionCoordinator)
        .modifier(TextSelectionCoordination())
        .navigationTitle("Speech Generation")
        .modifier(NavSubtitleIfAvailable(subtitle: subtitle))
        .toolbar { toolbarContent }
        .onAppear { validateModel() }
        .onChange(of: executor.models) { _, _ in validateModel() }
        .onChange(of: speech.selectedModelID) { _, _ in speech.resetVoices() }
        .task(id: ModelDetailRequest(context: executor.modelRequestContext, modelName: speech.selectedModelID ?? "", cacheRevision: executor.modelInfoCacheRevision)) {
            let context = executor.modelRequestContext
            guard let model = currentSelectedModel else { return }
            let response = await executor.fetchModelInfo(modelName: model.name, context: context)
            guard !Task.isCancelled, context == executor.modelRequestContext, speech.selectedModelID == model.id else { return }
            speech.setVoices(response?.voices)
        }
        .task {
            if serverManager.selectedServer != nil && !executor.initialFetchCompleted && !executor.isRunning && !executor.isPulling {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { appRefreshTrigger.send() }
            }
        }
        .alert("Error Occurred", isPresented: Binding(get: { speech.error != nil }, set: { if !$0 { speech.error = nil } })) {
            Button("OK") { speech.error = nil }
        } message: {
            Text(speech.error ?? "An unknown error occurred.")
        }
    }

    private func validateModel() {
        if let id = speech.selectedModelID, !executor.models.contains(where: { $0.id == id && $0.supportsSpeech }) {
            speech.selectedModelID = nil
            speech.resetVoices()
        }
    }

    @ViewBuilder
    private var speechRefreshButton: some View {
        Button(action: { appRefreshTrigger.send() }) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(executor.isRunning || executor.isPulling)
        .help("Refresh")
    }

    @ViewBuilder
    private var speechModelPickerMenu: some View {
        @Bindable var speech = speech
        Menu {
            Section {
                Picker("Select Model", selection: $speech.selectedModelID) {
                    Text("Select Model").tag(nil as OllamaModel.ID?)
                }
                .pickerStyle(.inline)
            }
            Section {
                Picker("Models", selection: $speech.selectedModelID) {
                    let sortedModels = executor.models.filter { $0.supportsSpeech }.sorted(using: modelSettings.sortOrder(forChat: false))
                    ForEach(sortedModels) { model in
                        let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                        HStack {
                            Text(model.name)
                            if isRunning { Image(systemName: "tray.and.arrow.down") }
                        }
                        .tag(model.id as OllamaModel.ID?)
                    }
                }
                .pickerStyle(.inline)
            }
            if executor.models.filter({ $0.supportsSpeech }).isEmpty {
                Section {
                    if executor.isRunning {
                        Button(action: {}) { Text("Loading models...") }.disabled(true)
                    } else {
                        Button(action: {}) { Text("No models available") }.disabled(true)
                    }
                }
            }
        } label: {
            let selectedModelName = executor.models.first(where: { $0.id == speech.selectedModelID })?.name
            Label(selectedModelName ?? String(localized: "Select Model"), systemImage: speech.selectedModelID != nil ? "tray.full.fill" : "tray.full")
#if os(visionOS)
                .labelStyle(.titleAndIcon)
#endif
        }
        .help({
            if let selectedModelName = executor.models.first(where: { $0.id == speech.selectedModelID })?.name {
                return String(format: NSLocalizedString("Select Model (%@ Selected)", comment: "モデルが選択されている時のツールチップ。"), selectedModelName)
            }
            return String(localized: "Select Model")
        }())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var speech = speech
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            speechRefreshButton
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Select Model", selection: $speech.selectedModelID) {
                Text("Select Model").tag(nil as OllamaModel.ID?)
                Divider()
                let sortedModels = executor.models.filter { $0.supportsSpeech }.sorted(using: modelSettings.sortOrder(forChat: false))
                ForEach(sortedModels) { model in
                    let isRunning = executor.runningModels.contains(where: { $0.name == model.name })
                    HStack {
                        Text(model.name)
                        if isRunning { Image(systemName: "tray.and.arrow.down") }
                    }
                    .tag(model.id as OllamaModel.ID?)
                }
                if executor.models.filter({ $0.supportsSpeech }).isEmpty {
                    Divider()
                    if executor.isRunning {
                        Text("Loading models...")
                            .tag("loading-speech-models-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    } else {
                        Text("No models available")
                            .tag("no-speech-models-available-tag" as OllamaModel.ID?)
                            .selectionDisabled(true)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelStyle(.titleAndIcon)
            .buttonSizingFlexibleIfAvailable()
            .frame(width: 150)
        }
#else
#if os(iOS)
        if #available(iOS 27.0, *) {
            ToolbarItemGroup(placement: .primaryAction) {
                speechRefreshButton
                speechModelPickerMenu
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                speechRefreshButton
                speechModelPickerMenu
            }
        }
#else
        ToolbarItemGroup(placement: .primaryAction) {
            speechRefreshButton
            speechModelPickerMenu
        }
#endif
#endif

#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif

        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                if !speech.messages.isEmpty { showingClearConfirm = true }
            }) {
                Label("New Generation", systemImage: "square.and.pencil")
            }
            .disabled(speech.messages.isEmpty)
            .help("New Generation")
            .confirmationDialog(String(localized: "Are you sure you want to clear the speech generation history?"), isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button(String(localized: "Clear History"), role: .destructive) {
                    speech.clear()
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
        }

#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif

#if !os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: { onToggleInspector() }) {
                Label("Inspector", systemImage: (isNativeVisionOS || isiOSAppOnVision) ? "info.circle" : (horizontalSizeClass == .compact ? "info.circle" : "sidebar.trailing"))
            }
            .help("Inspector")
        }
#endif
    }

    private func generateSpeech(retryID: UUID? = nil) {
        guard let model = currentSelectedModel, let host = serverManager.selectedServer?.host else { return }
        let context = executor.modelRequestContext
        speech.generate(baseURL: host, model: model, retryID: retryID) {
            // 最初の音声を受信した時点で、チャットと同様にロード済み表示を更新する。
            Task { @MainActor in
                guard context == executor.modelRequestContext else { return }
                _ = await executor.fetchRunningModels()
            }
        }
        scrollToBottomTrigger += 1
    }

    private func retrySpeech(for messageID: UUID, with message: ChatMessage) {
        generateSpeech(retryID: messageID)
    }
}
