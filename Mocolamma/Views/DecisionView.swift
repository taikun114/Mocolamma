import SwiftUI
import UniformTypeIdentifiers

struct DecisionView: View {
    @Environment(DecisionSession.self) private var session
    @Environment(CommandExecutor.self) private var executor
    @Environment(ServerManager.self) private var serverManager
    @Environment(RefreshTrigger.self) private var refreshTrigger
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var showingInspector: Bool
    var onToggleInspector: () -> Void
    @State private var buttonFrame: CGRect = .null
    @State private var conditionRowFrame: CGRect = .null
    @State private var viewportFrame: CGRect = .zero
    @State private var showingResetConfirmation = false
    @State private var showingModeConfirmation = false
    @State private var showingVisionWarning = false
    @State private var showingVisionPDFWarning = false
    @State private var attachmentDropContext = AttachmentDropContext()
    @State private var attachmentDropFrame: CGRect = .zero
    private var modelSettings = ModelSettingsManager.shared

    private var isCompact: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }
    private var selectedModel: OllamaModel? { executor.models.first { $0.id == session.selectedModelID } }
    private var screenDropTypes: [UTType] {
#if os(visionOS)
        AttachmentReorderDrag.acceptedContentTypes
#else
        AttachmentReorderDrag.externalContentTypes
#endif
    }
    private var models: [OllamaModel] {
        executor.models.filter { $0.capabilities?.contains("decision") == true }
            .sorted(using: modelSettings.sortOrder(forChat: true))
    }

    var body: some View {
        GeometryReader { geometry in
            if isCompact || geometry.size.width < 760 {
                compactContent
            } else {
                DecisionColumns {
                    Form { inputSection; conditionsSection }
                    .formStyle(.grouped)
#if os(visionOS)
                    .environment(\.defaultMinListRowHeight, 0)
#endif
#if os(iOS)
                    .contentMargins(.trailing, 16, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
#endif
                    .modifier(DecisionBottomBar { evaluateButton.padding() })
                } results: {
                    ScrollViewReader { proxy in
                        Form { resultsSection }.formStyle(.grouped)
#if os(iOS)
                            .contentMargins(.leading, 16, for: .scrollContent)
        #endif
                            .onChange(of: session.resultRevision) { _, _ in
                                withAnimation { proxy.scrollTo("decision-results", anchor: .top) }
                            }
                    }
                }
            }
        }
#if os(visionOS)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { attachmentDropFrame = $0 }
        .onDrop(of: screenDropTypes, delegate: AttachmentScreenDropDelegate(
            context: attachmentDropContext, origin: attachmentDropFrame.origin,
            isEnabled: !session.isRunning && selectedModel != nil && (!session.isJSON || selectedModel?.supportsVision == true),
            executor: executor
        ))
#endif
#if os(iOS)
        .background {
            ExternalAttachmentDropBridge(context: attachmentDropContext, executor: executor,
                                         isEnabled: !session.isRunning && selectedModel != nil && (!session.isJSON || selectedModel?.supportsVision == true))
        }
        .overlay {
            if attachmentDropContext.isExternalDragActive {
                ExternalAttachmentDropBridge(context: attachmentDropContext, executor: executor,
                                             isEnabled: !session.isRunning && selectedModel != nil && (!session.isJSON || selectedModel?.supportsVision == true),
                                             capturesDrop: true)
            }
        }
        .onDisappear { attachmentDropContext.isExternalDragActive = false }
#endif
        .navigationTitle("Decision")
#if os(iOS)
        .navigationBarTitleDisplayMode(isCompact ? .automatic : .inline)
#endif
        .modifier(NavSubtitleIfAvailable(subtitle: serverManager.selectedServer.map { Text(verbatim: $0.name) } ?? Text("No Server Selected")))
        .toolbar { toolbarContent }
        .modifier(ImagePreviewPresenter())
        .alert("Error Occurred", isPresented: Binding(
            get: { session.error != nil },
            set: { if !$0 { session.error = nil } }
        )) {
            Button("OK") { session.error = nil }.keyboardShortcut(.defaultAction)
        } message: {
            Text(verbatim: session.error ?? "")
        }
        .confirmationDialog("Switch to JSON input and remove non-image attachments?", isPresented: $showingModeConfirmation, titleVisibility: .visible) {
            Button("Switch to JSON", role: .destructive) { session.attachments = []; session.isJSON = true }
            Button("Cancel", role: .cancel) { }
        }
        .alert("This model does not support images", isPresented: $showingVisionWarning) {
            Button("Send") { evaluateSkippingImages() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if let name = selectedModel?.name {
                Text("The selected model \"\(name)\" does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            } else {
                Text("The selected model does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            }
        }
        .alert("This model does not support images", isPresented: $showingVisionPDFWarning) {
            Button("Send") { evaluateSkippingImages() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if !session.images.isEmpty {
                Text("The selected model does not support image recognition, so images will not be sent. Are you sure you want to send it as is?")
            }
            if let name = selectedModel?.name {
                Text("The selected model \"\(name)\" does not support image recognition, so attached PDF files will only be sent as extracted text. Are you sure you want to send it as is?\n\nTip: Switching to a vision-capable model will allow it to recognize images and layouts in addition to text.")
            } else {
                Text("The selected model does not support image recognition, so attached PDF files will only be sent as extracted text. Are you sure you want to send it as is?\n\nTip: Switching to a vision-capable model will allow it to recognize images and layouts in addition to text.")
            }
        }
        .onChange(of: executor.modelRequestContext) { _, _ in session.cancel(); session.selectedModelID = nil; session.result = nil; session.error = nil }
        .onAppear {
            if let id = session.selectedModelID, !executor.models.contains(where: { $0.id == id }) { session.selectedModelID = nil }
        }
        .onChange(of: executor.models) { _, models in
            if let id = session.selectedModelID, !models.contains(where: { $0.id == id }) { session.selectedModelID = nil }
        }
        .task {
            if serverManager.selectedServer != nil && !executor.initialFetchCompleted && !executor.isRunning && !executor.isPulling {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled { refreshTrigger.send() }
            }
        }
    }

    private var compactContent: some View {
        ScrollViewReader { proxy in
        Form {
            inputSection
            conditionsSection
#if os(macOS)
            Section {} footer: {
                inlineEvaluateButton
                    .padding(.horizontal, -10)
                    .padding(.bottom, -20)
            }
#else
            Section {
                inlineEvaluateButton
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
#endif
            resultsSection
        }
        .formStyle(.grouped)
#if os(visionOS)
        .environment(\.defaultMinListRowHeight, 0)
#endif
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
        .onChange(of: session.resultRevision) { _, _ in
            withAnimation { proxy.scrollTo("decision-results", anchor: .top) }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewportFrame = $0 }
        .overlay(alignment: .bottom) {
            if showsEvaluateButtonOverlay {
                GeometryReader { overlayGeometry in
                    let overlayFrame = overlayGeometry.frame(in: .global)
                    let targetFrame = conditionRowFrame.isNull ? buttonFrame : conditionRowFrame
#if os(visionOS)
                    let bottomInset = targetFrame.isNull ? 16 : max(0, targetFrame.minX - overlayFrame.minX)
#else
                    let bottomInset: CGFloat = 0
#endif
                    evaluateButton
                        .frame(width: targetFrame.isNull ? max(0, overlayGeometry.size.width - 32) : targetFrame.width)
#if os(visionOS)
                        .frame(height: evaluateButtonAreaHeight, alignment: .bottom)
#else
                        .frame(height: evaluateButtonAreaHeight, alignment: .center)
#endif
                        .position(
                            x: targetFrame.isNull ? overlayGeometry.size.width / 2 : targetFrame.midX - overlayFrame.minX,
                            y: isEvaluateButtonPinned
                                ? overlayGeometry.size.height - evaluateButtonAreaHeight / 2 - bottomInset
                                : buttonFrame.midY - overlayFrame.minY
                        )
                }
#if os(iOS)
                .clipped()
#endif
                .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        }
    }

    private var evaluateButtonAreaHeight: CGFloat {
#if os(macOS)
        56
#else
        76
#endif
    }

    private var showsEvaluateButtonOverlay: Bool {
#if os(iOS)
        isEvaluateButtonPinned || buttonFrame.intersects(viewportFrame)
#else
        isEvaluateButtonPinned
#endif
    }

    private var usesEvaluateButtonOverlay: Bool {
#if os(iOS)
        true
#else
        isEvaluateButtonPinned
#endif
    }

    private var inlineEvaluateButton: some View {
        evaluateButton
            .frame(height: evaluateButtonAreaHeight, alignment: .center)
            .opacity(usesEvaluateButtonOverlay ? 0 : 1)
            .allowsHitTesting(!usesEvaluateButtonOverlay)
            .accessibilityHidden(usesEvaluateButtonOverlay)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                buttonFrame = $0
            }
    }

    private var isEvaluateButtonPinned: Bool {
        buttonFrame.isNull || buttonFrame.minY - viewportFrame.minY > viewportFrame.height - evaluateButtonAreaHeight
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .primaryAction) { refreshButton }
        ToolbarItem(placement: .primaryAction) {
            modelPicker
                .pickerStyle(.menu)
                .labelStyle(.titleAndIcon)
                .buttonSizingFlexibleIfAvailable()
                .frame(width: 150)
        }
        ToolbarItem(placement: .primaryAction) { newDecisionButton }
#else
#if os(iOS)
        if #available(iOS 27.0, *) {
            ToolbarItemGroup(placement: .primaryAction) {
                refreshButton
                modelMenu
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                refreshButton
                modelMenu
            }
        }
#else
        ToolbarItemGroup(placement: .primaryAction) {
            refreshButton
            modelMenu
        }
#endif
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif
        ToolbarItem(placement: .primaryAction) { newDecisionButton }
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
#endif
        ToolbarItem(placement: .primaryAction) {
            Button(action: onToggleInspector) {
                Label("Inspector", systemImage: isCompact || isNativeVisionOS || isiOSAppOnVision ? "info.circle" : "sidebar.trailing")
            }
            .help("Toggle Inspector")
        }
#endif
    }

    private var refreshButton: some View {
        Button { refreshTrigger.send() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            .help("Refresh models")
            .disabled(executor.isRunning || executor.isPulling)
    }

    private var newDecisionButton: some View {
        Button { showingResetConfirmation = true } label: { Label("New Decision", systemImage: "square.and.pencil") }
            .help("Reset decision input and results")
            .disabled(!session.hasDraft && !session.isRunning)
            .confirmationDialog("Reset decision input and results?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("New Decision", role: .destructive) { session.reset() }
                Button("Cancel", role: .cancel) { }
            }
    }

    private var modelPicker: some View {
        @Bindable var session = session
        return Picker("Select Model", selection: $session.selectedModelID) {
            Text("Select Model").tag(nil as String?)
            Divider()
            ForEach(models) { model in
                HStack {
                    Text(model.name)
                    if executor.runningModels.contains(where: { $0.name == model.name }) {
                        Image(systemName: "tray.and.arrow.down")
                    }
                }
                .tag(Optional(model.id))
            }
            if models.isEmpty {
                Divider()
                if executor.isRunning {
                    Text("Loading models...")
                        .tag("loading-models-tag" as String?)
                        .selectionDisabled(true)
                } else {
                    Text("No models available")
                        .tag("no-models-available-tag" as String?)
                        .selectionDisabled(true)
                }
            }
        }
        .help("Select a decision model")
    }

    private var modelMenu: some View {
        @Bindable var session = session
        return Menu {
            Section {
                Picker("Select Model", selection: $session.selectedModelID) {
                    Text("Select Model").tag(nil as String?)
                }
                .pickerStyle(.inline)
            }
            Section {
                Picker("Models", selection: $session.selectedModelID) {
                    ForEach(models) { model in
                        HStack {
                            Text(model.name)
                            if executor.runningModels.contains(where: { $0.name == model.name }) {
                                Image(systemName: "tray.and.arrow.down")
                            }
                        }
                        .tag(Optional(model.id))
                    }
                }
                .pickerStyle(.inline)
            }
            if models.isEmpty {
                Section {
                    Button(action: {}) {
                        if executor.isRunning { Text("Loading models...") }
                        else { Text("No models available") }
                    }
                    .disabled(true)
                }
            }
        } label: {
            Label(selectedModel?.name ?? String(localized: "Select Model"), systemImage: session.selectedModelID != nil ? "tray.full.fill" : "tray.full")
#if os(visionOS)
                .labelStyle(.titleAndIcon)
#endif
        }
        .help(selectedModel.map { String(format: NSLocalizedString("Select Model (%@ Selected)", comment: "モデルが選択されている時のツールチップ。"), $0.name) } ?? String(localized: "Select Model"))
    }

    private var decisionAttachmentSpacing: CGFloat {
        if !session.images.isEmpty || !session.attachments.isEmpty {
            return 4
        }
#if os(macOS)
        return 10
#else
        return 12
#endif
    }

    private var inputSection: some View {
        @Bindable var session = session
        return Section("Decision Content") {
            VStack(alignment: .leading, spacing: decisionAttachmentSpacing) {
                VStack(alignment: .leading, spacing: 12) {
#if os(macOS)
                    AdaptiveSegmentedPickerRow(title: "Content to Evaluate") {
                        inputModePicker
                    }
                    .padding(.top, 6)
#else
                    inputModePicker
                    .pickerStyle(.menu)
#if os(visionOS)
                    .padding(.bottom, 10)
#endif
#endif
                TextEditor(text: $session.input)
                    .font(session.isJSON ? .system(.body, design: .monospaced) : .body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 120)
                    .padding(6)
                    .modifier(DecisionInputStyle(isInvalid: session.isJSONInvalid))
                    .accessibilityLabel("Content to Evaluate")
                    .accessibilityIdentifier("decision_input")
                if session.isJSONInvalid {
                    Text("Enter a valid JSON object or array.").font(.caption).foregroundStyle(.red)
                }
                }
#if !os(visionOS)
                decisionAttachments
#endif
            }
            .disabled(session.isRunning)
#if os(visionOS)
            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
#endif
#if os(visionOS)
            decisionAttachments
                .disabled(session.isRunning)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
#endif
        }
    }

    private var decisionAttachments: some View {
        @Bindable var session = session
        return MessageInputView(inputText: .constant(""), attachmentOnly: true, imagesOnly: session.isJSON,
                                selectedImages: $session.images, selectedAttachments: $session.attachments,
                                isStreaming: $session.isRunning, showingInspector: $showingInspector,
                                selectedModel: selectedModel, sendMessage: {},
                                attachmentDropContext: attachmentDropContext)
    }

    private var inputModePicker: some View {
        Picker("Content to Evaluate", selection: Binding(get: { session.isJSON }, set: { value in
            if value && !session.attachments.isEmpty { showingModeConfirmation = true } else { session.isJSON = value }
        })) {
            Text("Text").tag(false)
            Text("JSON").tag(true)
        }
    }

    private var conditionsSection: some View {
        @Bindable var session = session
        return Section("Decision Conditions") {
            DecisionConditionsEditor(conditions: $session.conditions)
                .disabled(session.isRunning)
#if os(iOS)
                .listRowBackground(
                    Color(uiColor: .secondarySystemGroupedBackground)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            conditionRowFrame = $0
                        }
                )
#endif
        }
    }

    private var evaluateButton: some View {
        Button {
            if session.isRunning { session.cancel() }
            else if let base = executor.apiBaseURL, let model = selectedModel {
#if !os(macOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
                if !model.supportsVision && session.attachments.contains(where: \.isPDF) {
                    showingVisionPDFWarning = true
                } else if !model.supportsVision && !session.images.isEmpty {
                    showingVisionWarning = true
                } else {
                    evaluate(baseURL: base, model: model)
                }
            }
        } label: {
            HStack {
                Spacer()
                if session.isRunning { Image(systemName: "stop.fill") }
                Text(session.isRunning ? "Cancel" : "Evaluate").fontWeight(.bold)
                Spacer()
                if !session.isRunning { Image(systemName: "arrow.right") }
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(DecisionProminentStyle())
        .disabled(!session.isRunning && (selectedModel.map { !session.canEvaluate(model: $0) } ?? true || executor.apiBaseURL == nil))
        .help(session.isRunning ? "Cancel the current decision" : "Evaluate the content using the selected conditions")
        .accessibilityIdentifier("decision_evaluate")
    }

    private func evaluateSkippingImages() {
        guard let base = executor.apiBaseURL, let model = selectedModel else { return }
        evaluate(baseURL: base, model: model, skipImages: true)
    }

    private func evaluate(baseURL: String, model: OllamaModel, skipImages: Bool = false) {
        session.evaluate(baseURL: baseURL, model: model, skipImages: skipImages) {
            guard executor.apiBaseURL == baseURL else { return }
            Task { _ = await executor.fetchRunningModels() }
        }
    }

    private var resultsSection: some View {
        Section {
            if session.isRunning {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if let result = session.result {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(session.resultConditions.enumerated()), id: \.element.id) { index, condition in
                        if let answer = result.answers[condition.id.uuidString] {
                            DecisionResultRow(condition: condition, answer: answer, number: index + 1)
                            if index < session.resultConditions.count - 1 { Divider() }
                        }
                    }
                }
                .id(session.resultRevision)
            } else {
                Text("Decision results will appear here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        } header: {
            Text("Decision Results")
        } footer: {
            DecisionResultFooter(session: session, resultText: resultText, resultJSON: resultJSON, copy: copy)
        }
        .id("decision-results")
    }

    private var resultText: String {
        DecisionResultFormatter.text(conditions: session.resultConditions, response: session.result)
    }
    private var resultJSON: String {
        DecisionResultFormatter.json(conditions: session.resultConditions, response: session.result)
    }
    private func copy(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
    }
}

private struct DecisionResultFooter: View {
    let session: DecisionSession
    let resultText: String
    let resultJSON: String
    let copy: (String) -> Void

    var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            copyButtons
                            Spacer(minLength: 0)
                            shareButton
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { copyButtons }
                                VStack(alignment: .leading, spacing: 8) { copyButtons }
                            }
                            shareButton
                        }
                    }
#if os(visionOS)
                    .buttonStyle(.bordered)
#else
                    .buttonStyle(.borderless)
#endif
                    .disabled(session.result == nil || session.isRunning)
                    if let result = session.result {
                        let lines = statisticsLines(for: result)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(lines.indices, id: \.self) { index in
                                Text(verbatim: lines[index])
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Copy", systemImage: SFSymbol.copy) {
                                copy(lines.joined(separator: "\n"))
                            }
                        }
                    }
            }
            .textCase(nil)
#if os(iOS)
            .padding(.bottom, 24)
#endif
    }
    private func statisticsLines(for result: DecisionResponse) -> [String] {
        var lines = [
            String(localized: "Model") + ": " + result.model,
            String(localized: "Response time: \(session.elapsed * 1000, format: .number.precision(.fractionLength(2))) ms"),
            String(localized: "Input tokens: \(result.usage.input_tokens)")
        ]
        if let cached = result.prompt_eval_cached_count {
            lines.append(String(localized: "Cache hit: \(result.cacheHitRate ?? 0, format: .percent.precision(.fractionLength(2))) (\(cached) tokens)"))
        }
        return lines
    }

    @ViewBuilder private var copyButtons: some View {
        Button { copy(resultText) } label: {
            Label("Copy Results", systemImage: SFSymbol.copy).fixedSize(horizontal: true, vertical: false)
        }
        .help("Copy Results")
        Button { copy(resultJSON) } label: {
            Label("Copy JSON", systemImage: "curlybraces").fixedSize(horizontal: true, vertical: false)
        }
        .help("Copy JSON")
    }

    private var shareButton: some View {
        ShareLink(item: resultText) {
            Label("Share", systemImage: "square.and.arrow.up").fixedSize(horizontal: true, vertical: false)
        }
        .help("Share decision results")
    }

}

private struct DecisionProminentStyle: ViewModifier {
    func body(content: Content) -> some View {
#if !os(visionOS)
        if #available(macOS 26, iOS 26, *) {
            content.buttonStyle(.glassProminent).controlSize(.extraLarge)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        }
#else
        content.buttonStyle(.borderedProminent).controlSize(.extraLarge)
            .tint(Color.accentColor)
#endif
    }
}

private struct DecisionBottomBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar
    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            content.safeAreaBar(edge: .bottom) { bar() }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { bar() }
        }
    }
}

#Preview("Decision Screen") {
    let hasResult = false
    let serverManager = ServerManager()
    let executor = {
        let executor = CommandExecutor(serverManager: serverManager)
        executor.initialFetchCompleted = true
        return executor
    }()
    let session = {
        let session = DecisionSession()
        let condition = DecisionCondition(instructions: "Classify this report.", options: ["Bug report", "Feature request"])
        session.conditions = [condition]
        session.input = "The app crashes on launch."
        session.resultConditions = [condition]
        if hasResult { session.result = DecisionResponse(model: "Preview Model", answers: [condition.id.uuidString: DecisionAnswer(type: "choice", choice: "Bug report", noul: nil, score: nil, legend: nil, probabilities: ["Bug report": 0.92, "Feature request": 0.08], confidence: nil)], usage: .init(input_tokens: 100, output_tokens: 0), prompt_eval_cached_count: 25) }
        return session
    }()
    NavigationStack {
        DecisionView(showingInspector: .constant(false), onToggleInspector: {})
            .defaultScrollAnchor(.bottom)
    }
    .environment(serverManager)
    .environment(executor)
    .environment(session)
    .environment(RefreshTrigger())
#if os(macOS)
    .frame(width: 1100, height: 700)
#endif
}

#Preview("Result Footer") {
    Form {
        Section {
            Text("Decision results will appear here.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
        } header: {
            Text("Decision Results")
        } footer: {
            DecisionResultFooter(session: DecisionSession(), resultText: "", resultJSON: "", copy: { _ in })
        }
    }
    .formStyle(.grouped)
    .environment(DecisionSession())
}
