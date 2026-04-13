import SwiftUI
import Foundation
import CompactSlider

// MARK: - インスペクターコンテンツヘルパービュー
struct InspectorContentView: View {
    @Environment(CommandExecutor.self) var commandExecutor
    @Environment(ChatSettings.self) var chatSettings
    @Environment(ImageGenerationSettings.self) var imageSettings
    let selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    let sortedModels: [OllamaModel]
    let selectedServerForInspector: ServerInfo?
    var serverManager: ServerManager
    @Binding var showingInspector: Bool
    @Binding var selectedFilterTag: String?
    
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var isSystemPromptFocused: Bool
    @FocusState private var isCustomWidthFocused: Bool
    @FocusState private var isCustomHeightFocused: Bool
    @FocusState private var isCustomStepsFocused: Bool
    @FocusState private var isCustomKeepAliveFocused: Bool
    @FocusState private var isChatSeedFocused: Bool
    @FocusState private var isRepeatLastNFocused: Bool
    @FocusState private var isNumPredictFocused: Bool
    @FocusState private var isTopKFocused: Bool
    @State private var inspectorWidth: CGFloat = 0 // インスペクターの幅を保持
    
    private var vStackSpacing: CGFloat {
#if os(macOS)
        return 8
#elseif os(visionOS)
        return 16
#else
        if #available(iOS 26.0, *) {
            return 16
        } else {
            return 8
        }
#endif
    }
    
    private var isCompactLayout: Bool {
#if os(visionOS)
        // visionOSでは常に通常のレイアウト（1x4）を使用する
        return false
#elseif os(iOS)
        // iOS（iPad含む）で幅が320未満の場合にコンパクトレイアウト（2x2）を適用
        return inspectorWidth > 0 && inspectorWidth < 320
#else
        // macOSでは常に通常のレイアウト（1x4）
        return false
#endif
    }
    
    var body: some View {
        @Bindable var chatSettings = chatSettings
        @Bindable var imageSettings = imageSettings
        
        Group {
            if selection == "models" {
                if let selectedModelID = selectedModel,
                   let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                    ModelInspectorDetailView(model: model, selectedFilterTag: $selectedFilterTag)
                        .id(model.id)
                } else {
                    Text("Select a model to see the details.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .id("model_selection_placeholder")
                        .padding()
                }
            } else if selection == "server" {
                if let server = selectedServerForInspector {
                    ServerInspectorDetailView(
                        server: server,
                        connectionStatus: serverManager.serverConnectionStatuses[server.id] ?? nil
                    )
                    .id(server.id)
                } else {
                    Text("Select a server to see the details.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .id("server_selection_placeholder")
                        .padding()
                }
            } else if selection == "chat" {
                Form {
                    Section("Chat Settings") {
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle("Stream Response", isOn: $chatSettings.isStreamingEnabled)
                            
                            Text("If you turn off stream response, it is recommended to set the API timeout to unlimited in the settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        keepAlivePicker(option: $chatSettings.keepAliveOption, customValue: $chatSettings.customKeepAliveValue, customUnit: $chatSettings.customKeepAliveUnit)
                        
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Picker("Thinking", selection: $chatSettings.thinkingOption) {
                                ForEach(ThinkingOption.allCases) { option in
                                    Text(option.localizedName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(!(chatSettings.selectedModelCapabilities?.contains("thinking") ?? false))
                            .onChange(of: chatSettings.selectedModelCapabilities) { _, caps in
                                let hasThinking = caps?.contains("thinking") ?? false
                                if !hasThinking { chatSettings.thinkingOption = .none }
                            }
                            
                            Text("Specifies whether to perform inference when using a reasoning model.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Toggle(isOn: $chatSettings.isSystemPromptEnabled) {
                                Text("System Prompt")
                            }
                            TextEditor(text: $chatSettings.systemPrompt)
                                .focused($isSystemPromptFocused) // ここにフォーカス状態をバインド
                                .frame(height: 100)
                                .disabled(!chatSettings.isSystemPromptEnabled)
                                .foregroundColor(chatSettings.isSystemPromptEnabled ? .primary : .secondary)
                                .scrollContentBackground(.hidden)
                                .background(chatSettings.isSystemPromptEnabled ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            colorSchemeContrast == .increased 
                                            ? (chatSettings.isSystemPromptEnabled ? Color.primary : Color.secondary) 
                                            : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Section("Custom Settings") {
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle("Enable Custom Settings", isOn: $chatSettings.useCustomChatSettings)
                            Text("Enables advanced options to adjust the model's behavior.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        chatSeedSettingsSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            VStack {
                                Toggle(isOn: $chatSettings.isTemperatureEnabled) {
                                    Text("Temperature")
                                }
                                .padding(.bottom, 4)
                                HStack {
                                    CompactSlider(value: $chatSettings.chatTemperature, in: 0.0...2.0, step: 0.1)
                                        .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                                        .frame(height: 32)
#else
                                        .frame(height: 16)
#endif
                                    Text(String(format: "%.1f", chatSettings.chatTemperature))
                                        .font(.body.monospaced())
                                        .foregroundStyle(chatSettings.isTemperatureEnabled ? .secondary : .tertiary)
                                }
                                .disabled(!chatSettings.isTemperatureEnabled)
                                .foregroundColor(chatSettings.isTemperatureEnabled ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("Specifies the model temperature. Increasing the temperature makes the response more creative, while decreasing it makes it more accurate.")
                                .font(.caption)
                                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(!chatSettings.useCustomChatSettings)
                        .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            VStack {
                                Toggle(isOn: $chatSettings.isContextWindowEnabled) {
                                    Text("Context Window")
                                }
                                .padding(.bottom, 4)
                                HStack {
                                    CompactSlider(value: $chatSettings.contextWindowValue, in: 512...Double(chatSettings.selectedModelContextLength ?? 4096), step: 128.0)
                                        .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                                        .frame(height: 32)
#else
                                        .frame(height: 16)
#endif
                                    Text("\(Int(chatSettings.contextWindowValue))")
                                        .font(.body.monospaced())
                                        .foregroundStyle(chatSettings.isContextWindowEnabled ? .secondary : .tertiary)
                                }
                                .disabled(!chatSettings.isContextWindowEnabled)
                                .foregroundColor(chatSettings.isContextWindowEnabled ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("Specifies the maximum number of tokens the model can remember (reference) during a session.")
                                .font(.caption)
                                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(!chatSettings.useCustomChatSettings)
                        .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        repeatLastNSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        repeatPenaltySection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        numPredictSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        topKSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        topPSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        minPSection
                            .disabled(!chatSettings.useCustomChatSettings)
                            .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
#if !os(macOS)
                .onTapGesture {
                    isSystemPromptFocused = false // キーボードを閉じる
                    isCustomKeepAliveFocused = false
                    isChatSeedFocused = false
                    isRepeatLastNFocused = false
                    isNumPredictFocused = false
                    isTopKFocused = false
                }
#endif
            } else if selection == "image_generation" {
                Form {
                    Section("Image Generation Settings") {
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle("Stream Response", isOn: $imageSettings.isStreamingEnabled)
                            
                            Text("If you turn off stream response, it is recommended to set the API timeout to unlimited in the settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        keepAlivePicker(option: $imageSettings.keepAliveOption, customValue: $imageSettings.customKeepAliveValue, customUnit: $imageSettings.customKeepAliveUnit)
                        
                        widthSettingsSection
                        heightSettingsSection
                        stepsSettingsSection
                        seedSettingsSection
                    }
                    
                    Section("Custom Settings") {
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle(isOn: $imageSettings.customWidthEnabled) {
                                Text("Custom Width")
                                    .foregroundStyle(.primary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom width", value: $imageSettings.customWidth, format: .number.grouping(.never))
                                    .focused($isCustomWidthFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if !os(macOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customWidthEnabled)
                                
                                Stepper("Adjust custom width", value: $imageSettings.customWidth, in: 64...65536, step: 8)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customWidthEnabled)
                            }
                            Text("Enter the desired image width as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle(isOn: $imageSettings.customHeightEnabled) {
                                Text("Custom Height")
                                    .foregroundStyle(.primary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom height", value: $imageSettings.customHeight, format: .number.grouping(.never))
                                    .focused($isCustomHeightFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if !os(macOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customHeightEnabled)
                                
                                Stepper("Adjust custom height", value: $imageSettings.customHeight, in: 64...65536, step: 8)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customHeightEnabled)
                            }
                            Text("Enter the desired image height as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: vStackSpacing) {
                            Toggle(isOn: $imageSettings.customStepsEnabled) {
                                Text("Custom Steps")
                                    .foregroundStyle(.primary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom steps", value: $imageSettings.customSteps, format: .number.grouping(.never))
                                    .focused($isCustomStepsFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if !os(macOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customStepsEnabled)
                                
                                Stepper("Adjust custom steps", value: $imageSettings.customSteps, in: 1...1000, step: 1)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customStepsEnabled)
                            }
                            Text("Enter the number of image generation steps as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
#if !os(macOS)
                .onTapGesture {
                    isCustomWidthFocused = false
                    isCustomHeightFocused = false
                    isCustomStepsFocused = false
                    isCustomKeepAliveFocused = false
                }
#endif
            } else {
                Text("Nothing to display.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("nothing_to_display_placeholder")
                    .padding()
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        inspectorWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        if abs(inspectorWidth - newWidth) > 1.0 {
                            inspectorWidth = newWidth
                        }
                    }
            }
        )
#if os(macOS)
        .toolbar {
            Spacer()
            Button {
                showingInspector.toggle()
            } label: {
                Label(showingInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .help("Toggle Inspector")
        }
#elseif os(visionOS)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 8)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
#endif
    }
    
    @ViewBuilder
    private var widthSettingsSection: some View {
        @Bindable var imageSettings = imageSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            HStack {
                Text("Width")
                    .foregroundStyle(imageSettings.customWidthEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.width)) px")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customWidthEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.width, in: 64...2048, step: 64)
                .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                .frame(height: 32)
#else
                .frame(height: 16)
#endif
                .disabled(imageSettings.customWidthEnabled)
            
            if isCompactLayout {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        widthButton(for: 384.0)
                        widthButton(for: 512.0)
                    }
                    HStack(spacing: 8) {
                        widthButton(for: 768.0)
                        widthButton(for: 1024.0)
                    }
                }
            } else {
                HStack {
                    ForEach([384.0, 512.0, 768.0, 1024.0], id: \.self) { size in
                        widthButton(for: size)
                    }
                }
            }
            
            Text("Specifies the width of the image you want to generate.")
                .font(.caption)
                .foregroundStyle(imageSettings.customWidthEnabled ? .tertiary : .secondary)
        }
    }
    
    @ViewBuilder
    private var heightSettingsSection: some View {
        @Bindable var imageSettings = imageSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            HStack {
                Text("Height")
                    .foregroundStyle(imageSettings.customHeightEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.height)) px")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customHeightEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.height, in: 64...2048, step: 64)
                .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                .frame(height: 32)
#else
                .frame(height: 16)
#endif
                .disabled(imageSettings.customHeightEnabled)
            
            if isCompactLayout {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        heightButton(for: 384.0)
                        heightButton(for: 512.0)
                    }
                    HStack(spacing: 8) {
                        heightButton(for: 768.0)
                        heightButton(for: 1024.0)
                    }
                }
            } else {
                HStack {
                    ForEach([384.0, 512.0, 768.0, 1024.0], id: \.self) { size in
                        heightButton(for: size)
                    }
                }
            }
            
            Text("Specifies the height of the image you want to generate.")
                .font(.caption)
                .foregroundStyle(imageSettings.customHeightEnabled ? .tertiary : .secondary)
        }
    }
    
    @ViewBuilder
    private func widthButton(for size: Double) -> some View {
        if imageSettings.width == size {
            Button {
                imageSettings.width = size
            } label: {
                Text(String(format: "%.0f", size))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
#if os(visionOS)
            .tint(.accentColor.opacity(1.0))
            .foregroundStyle(.white.opacity(1.0))
#endif
            .controlSize(.small)
            .disabled(imageSettings.customWidthEnabled)
        } else {
            Button {
                imageSettings.width = size
            } label: {
                Text(String(format: "%.0f", size))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(imageSettings.customWidthEnabled)
        }
    }
    
    @ViewBuilder
    private func heightButton(for size: Double) -> some View {
        if imageSettings.height == size {
            Button {
                imageSettings.height = size
            } label: {
                Text(String(format: "%.0f", size))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
#if os(visionOS)
            .tint(.accentColor.opacity(1.0))
            .foregroundStyle(.white.opacity(1.0))
#endif
            .controlSize(.small)
            .disabled(imageSettings.customHeightEnabled)
        } else {
            Button {
                imageSettings.height = size
            } label: {
                Text(String(format: "%.0f", size))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(imageSettings.customHeightEnabled)
        }
    }
    
    @ViewBuilder
    private var stepsSettingsSection: some View {
        @Bindable var imageSettings = imageSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            HStack {
                Text("Steps")
                    .foregroundStyle(imageSettings.customStepsEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.steps))")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customStepsEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.steps, in: 1...20, step: 1)
                .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                .frame(height: 32)
#else
                .frame(height: 16)
#endif
                .disabled(imageSettings.customStepsEnabled)
            Text("Specifies the number of image generation steps. Increasing the number of steps increases generation time but can improve detail.")
                .font(.caption)
                .foregroundStyle(imageSettings.customStepsEnabled ? .tertiary : .secondary)
        }
    }
    
    @ViewBuilder
    private var chatSeedSettingsSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Toggle(isOn: $chatSettings.isSeedEnabled) {
                Text("Seed")
            }
            HStack(alignment: .center) {
                TextField("Enter seed value", value: $chatSettings.seed, format: .number.grouping(.never))
                    .focused($isChatSeedFocused)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
#if !os(macOS)
                    .keyboardType(.numberPad)
#endif
                    .disabled(!chatSettings.isSeedEnabled)
                
                Stepper("Adjust seed value", value: $chatSettings.seed, in: -OLLAMA_SEED_SAFE_LIMIT...OLLAMA_SEED_SAFE_LIMIT)
                    .labelsHidden()
                    .disabled(!chatSettings.isSeedEnabled)
            }
            .foregroundColor(chatSettings.isSeedEnabled ? .primary : .secondary)
            
            Text("Specifies the seed value used for text generation.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
        }
    }
    
    @ViewBuilder
    private var repeatLastNSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Picker("Repeat Last N", selection: $chatSettings.repeatLastNOption) {
                ForEach(RepeatLastNOption.allCases) { opt in
                    if opt == .max {
                        let contextValue = chatSettings.isContextWindowEnabled ? Int(chatSettings.contextWindowValue) : 2048
                        Text("RepeatLastN_Max \(contextValue)").tag(opt)
                    } else {
                        Text(opt.localizedName).tag(opt)
                    }
                }
            }
            .pickerStyle(.menu)
            
            if chatSettings.repeatLastNOption == .custom {
                HStack(alignment: .center) {
                    TextField("Enter Repeat Last N value", value: $chatSettings.repeatLastNValue, format: .number.grouping(.never))
                        .focused($isRepeatLastNFocused)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
#if !os(macOS)
                        .keyboardType(.numberPad)
#endif
                        .frame(maxWidth: .infinity)
                    
                    Stepper("Adjust Repeat Last N value", value: $chatSettings.repeatLastNValue, in: 1...2147483647, step: 1)
                        .labelsHidden()
                }
            }
            
            Text("Sets how far back for the model to look back to prevent repetition.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
        }
    }
    
    @ViewBuilder
    private var repeatPenaltySection: some View {
        @Bindable var chatSettings = chatSettings
        VStack {
            Toggle(isOn: $chatSettings.isRepeatPenaltyEnabled) {
                Text("Repeat Penalty")
            }
            .padding(.bottom, 4)
            HStack {
                CompactSlider(value: $chatSettings.repeatPenaltyValue, in: 0.0...2.0, step: 0.1)
                    .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                    .frame(height: 32)
#else
                    .frame(height: 16)
#endif
                Text(String(format: "%.1f", chatSettings.repeatPenaltyValue))
                    .font(.body.monospaced())
                    .foregroundStyle(chatSettings.isRepeatPenaltyEnabled ? .secondary : .tertiary)
            }
            .disabled(!chatSettings.isRepeatPenaltyEnabled)
            .foregroundColor(chatSettings.isRepeatPenaltyEnabled ? .primary : .secondary)
            
            Text("Sets how strongly to penalize repetitions.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var numPredictSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Picker("Num Predict", selection: $chatSettings.numPredictOption) {
                ForEach(NumPredictOption.allCases) { opt in
                    Text(opt.localizedName).tag(opt)
                }
            }
            .pickerStyle(.menu)
            
            if chatSettings.numPredictOption == .custom {
                HStack(alignment: .center) {
                    TextField("Enter Num Predict value", value: $chatSettings.numPredictValue, format: .number.grouping(.never))
                        .focused($isNumPredictFocused)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
#if !os(macOS)
                        .keyboardType(.numberPad)
#endif
                        .frame(maxWidth: .infinity)
                    
                    Stepper("Adjust Num Predict value", value: $chatSettings.numPredictValue, in: 0...2147483647, step: 1)
                        .labelsHidden()
                }
            }
            
            Text("Sets the maximum number of tokens to predict when generating text.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
        }
    }
    
    @ViewBuilder
    private var topKSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Toggle(isOn: $chatSettings.isTopKEnabled) {
                Text("Top-k")
            }
            HStack(alignment: .center) {
                TextField("Enter Top-k value", value: $chatSettings.topKValue, format: .number.grouping(.never))
                    .focused($isTopKFocused)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
#if !os(macOS)
                    .keyboardType(.numberPad)
#endif
                    .disabled(!chatSettings.isTopKEnabled)
                
                Stepper("Adjust Top-k value", value: $chatSettings.topKValue, in: 0...2147483647, step: 1)
                    .labelsHidden()
                    .disabled(!chatSettings.isTopKEnabled)
            }
            .foregroundColor(chatSettings.isTopKEnabled ? .primary : .secondary)
            
            Text("Reduces the probability of generating nonsense. A higher value like 100 will give more diverse answers, while a lower value like 10 will give more stable answers.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
        }
    }
    
    @ViewBuilder
    private var topPSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack {
            Toggle(isOn: $chatSettings.isTopPEnabled) {
                Text("Top-p")
            }
            .padding(.bottom, 4)
            HStack {
                CompactSlider(value: $chatSettings.topPValue, in: 0.0...1.0, step: 0.01)
                    .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                    .frame(height: 32)
#else
                    .frame(height: 16)
#endif
                Text(String(format: "%.2f", chatSettings.topPValue))
                    .font(.body.monospaced())
                    .foregroundStyle(chatSettings.isTopPEnabled ? .secondary : .tertiary)
            }
            .disabled(!chatSettings.isTopPEnabled)
            .foregroundColor(chatSettings.isTopPEnabled ? .primary : .secondary)
            
            Text("Works together with Top-k. A higher value like 0.95 will lead to more diverse text, while a lower value like 0.5 will generate more focused and stable text.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var minPSection: some View {
        @Bindable var chatSettings = chatSettings
        VStack {
            Toggle(isOn: $chatSettings.isMinPEnabled) {
                Text("Min-p")
            }
            .padding(.bottom, 4)
            HStack {
                CompactSlider(value: $chatSettings.minPValue, in: 0.0...1.0, step: 0.01)
                    .compactSliderOptionsByAdding(.precisionControl())
#if !os(macOS)
                    .frame(height: 32)
#else
                    .frame(height: 16)
#endif
                Text(String(format: "%.2f", chatSettings.minPValue))
                    .font(.body.monospaced())
                    .foregroundStyle(chatSettings.isMinPEnabled ? .secondary : .tertiary)
            }
            .disabled(!chatSettings.isMinPEnabled)
            .foregroundColor(chatSettings.isMinPEnabled ? .primary : .secondary)
            
            Text("An alternative to Top-p, aimed at ensuring a balance of quality and variety. It discourages low-quality responses by excluding tokens with a relative probability below a threshold (P) compared to the most likely token.")
                .font(.caption)
                .foregroundStyle(chatSettings.useCustomChatSettings ? .secondary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var seedSettingsSection: some View {
        @Bindable var imageSettings = imageSettings
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Toggle(isOn: $imageSettings.isSeedEnabled) {
                Text("Seed")
                    .foregroundStyle(.primary)
            }
            HStack(alignment: .center) {
                TextField("Enter seed value", value: $imageSettings.seed, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
#if !os(macOS)
                    .keyboardType(.numberPad)
#endif
                    .disabled(!imageSettings.isSeedEnabled)
                
                Stepper("Adjust seed value", value: $imageSettings.seed, in: -OLLAMA_SEED_SAFE_LIMIT...OLLAMA_SEED_SAFE_LIMIT)
                    .labelsHidden()
                    .disabled(!imageSettings.isSeedEnabled)
            }
            Text("Specifies the seed value used for image generation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func keepAlivePicker(option: Binding<KeepAliveOption>, customValue: Binding<Int>, customUnit: Binding<KeepAliveUnit>) -> some View {
        VStack(alignment: .leading, spacing: vStackSpacing) {
            Picker("Keep Alive", selection: option) {
                Text(KeepAliveOption.default.localizedName)
                    .tag(KeepAliveOption.default)
                
                Divider()
                
                ForEach(KeepAliveOption.allCases.filter { $0 != .default && $0 != .custom }) { opt in
                    Text(opt.localizedName).tag(opt)
                }
                
                Divider()
                
                Text(KeepAliveOption.custom.localizedName)
                    .tag(KeepAliveOption.custom)
            }
            .pickerStyle(.menu)
            
            if option.wrappedValue == .custom {
                HStack(alignment: .center) {
                    TextField("Enter Keep Alive Time", value: customValue, format: .number.grouping(.never))
                        .focused($isCustomKeepAliveFocused)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
#if !os(macOS)
                        .keyboardType(.numberPad)
#endif
                        .frame(maxWidth: .infinity)
                    
                    Stepper("Adjust Keep Alive Time", value: customValue, in: 1...3600, step: 1)
                        .labelsHidden()
                    
                    Picker("Unit", selection: customUnit) {
                        ForEach(KeepAliveUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            
            Text("Sets the time a model is kept in the Ollama server's memory.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
