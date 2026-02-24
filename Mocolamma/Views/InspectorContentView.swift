import SwiftUI
import Foundation
import CompactSlider

// MARK: - インスペクターコンテンツヘルパービュー
struct InspectorContentView: View {
    @Environment(CommandExecutor.self) var commandExecutor
    @EnvironmentObject var chatSettings: ChatSettings
    @EnvironmentObject var imageSettings: ImageGenerationSettings
    let selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    let sortedModels: [OllamaModel]
    let selectedServerForInspector: ServerInfo?
    @ObservedObject var serverManager: ServerManager
    @Binding var showingInspector: Bool
    
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var isSystemPromptFocused: Bool
    @FocusState private var isCustomWidthFocused: Bool
    @FocusState private var isCustomHeightFocused: Bool
    @FocusState private var isCustomStepsFocused: Bool
    @FocusState private var isCustomKeepAliveFocused: Bool
    @State private var inspectorWidth: CGFloat = 0 // インスペクターの幅を保持
    
    private var isCompactLayout: Bool {
#if os(iOS)
        // iOS（iPad含む）で幅が320未満の場合にコンパクトレイアウト（2x2）を適用
        return inspectorWidth > 0 && inspectorWidth < 320
#else
        // macOSでは常に通常のレイアウト（1x4）
        return false
#endif
    }
    
    var body: some View {
        Group {
            if selection == "models" {
                if let selectedModelID = selectedModel,
                   let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                    ModelInspectorDetailView(model: model)
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
                        Toggle(isOn: $chatSettings.isStreamingEnabled) {
                            Text("Stream Response")
                            Text("If you turn off stream response, it is recommended to set the API timeout to unlimited in the settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        keepAlivePicker(option: $chatSettings.keepAliveOption, customValue: $chatSettings.customKeepAliveValue, customUnit: $chatSettings.customKeepAliveUnit)
                        
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text("Thinking")
                                Text("Specifies whether to perform inference when using a reasoning model.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("Thinking", selection: $chatSettings.thinkingOption) {
                                ForEach(ThinkingOption.allCases) { option in
                                    Text(option.localizedName).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .disabled(!(chatSettings.selectedModelCapabilities?.contains("thinking") ?? false))
                            .onChange(of: chatSettings.selectedModelCapabilities) { _, caps in
                                let hasThinking = caps?.contains("thinking") ?? false
                                if !hasThinking { chatSettings.thinkingOption = .none }
                            }
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
                        Toggle("Enable Custom Settings", isOn: $chatSettings.useCustomChatSettings)
                        
                        VStack {
                            Toggle(isOn: $chatSettings.isTemperatureEnabled) {
                                Text("Temperature")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $chatSettings.chatTemperature, in: 0.0...2.0, step: 0.1)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text(String(format: "%.1f", chatSettings.chatTemperature))
                                    .font(.body.monospaced())
                            }
                            .disabled(!chatSettings.isTemperatureEnabled)
                            .foregroundColor(chatSettings.isTemperatureEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!chatSettings.useCustomChatSettings)
                        .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                        
                        VStack {
                            Toggle(isOn: $chatSettings.isContextWindowEnabled) {
                                Text("Context Window")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $chatSettings.contextWindowValue, in: 512...Double(chatSettings.selectedModelContextLength ?? 4096), step: 128.0)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text("\(Int(chatSettings.contextWindowValue))")
                                    .font(.body.monospaced())
                            }
                            .disabled(!chatSettings.isContextWindowEnabled)
                            .foregroundColor(chatSettings.isContextWindowEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!chatSettings.useCustomChatSettings)
                        .foregroundColor(chatSettings.useCustomChatSettings ? .primary : .secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
#if os(iOS)
                .onTapGesture {
                    isSystemPromptFocused = false // キーボードを閉じる
                    isCustomKeepAliveFocused = false
                }
#endif
            } else if selection == "image_generation" {
                Form {
                    Section("Image Generation Settings") {
                        Toggle(isOn: $imageSettings.isStreamingEnabled) {
                            Text("Stream Response")
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
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customWidthEnabled) {
                                Text("Custom Width")
                                    .foregroundStyle(imageSettings.customWidthEnabled ? .primary : .secondary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom width", value: $imageSettings.customWidth, format: .number.grouping(.never))
                                    .focused($isCustomWidthFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if os(iOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customWidthEnabled)
                                
                                Stepper("Adjust custom width", value: $imageSettings.customWidth, in: 64...65536, step: 8)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customWidthEnabled)
                            }
                            Text("Enter the desired image width as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.customWidthEnabled ? .secondary : .tertiary)
                        }
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customHeightEnabled) {
                                Text("Custom Height")
                                    .foregroundStyle(imageSettings.customHeightEnabled ? .primary : .secondary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom height", value: $imageSettings.customHeight, format: .number.grouping(.never))
                                    .focused($isCustomHeightFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if os(iOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customHeightEnabled)
                                
                                Stepper("Adjust custom height", value: $imageSettings.customHeight, in: 64...65536, step: 8)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customHeightEnabled)
                            }
                            Text("Enter the desired image height as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.customHeightEnabled ? .secondary : .tertiary)
                        }
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customStepsEnabled) {
                                Text("Custom Steps")
                                    .foregroundStyle(imageSettings.customStepsEnabled ? .primary : .secondary)
                            }
                            HStack(alignment: .center) {
                                TextField("Enter custom steps", value: $imageSettings.customSteps, format: .number.grouping(.never))
                                    .focused($isCustomStepsFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if os(iOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.customStepsEnabled)
                                
                                Stepper("Adjust custom steps", value: $imageSettings.customSteps, in: 1...1000, step: 1)
                                    .labelsHidden()
                                    .disabled(!imageSettings.customStepsEnabled)
                            }
                            Text("Enter the number of image generation steps as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.customStepsEnabled ? .secondary : .tertiary)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                inspectorWidth = geometry.size.width
                            }
                            .onChange(of: geometry.size.width) { _, newWidth in
                                inspectorWidth = newWidth
                            }
                    }
                )
#if os(iOS)
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
#endif
    }
    
    @ViewBuilder
    private var widthSettingsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Width")
                    .foregroundStyle(imageSettings.customWidthEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.width)) px")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customWidthEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.width, in: 64...2048, step: 64)
#if os(iOS)
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
        VStack(alignment: .leading) {
            HStack {
                Text("Height")
                    .foregroundStyle(imageSettings.customHeightEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.height)) px")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customHeightEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.height, in: 64...2048, step: 64)
#if os(iOS)
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
        VStack(alignment: .leading) {
            HStack {
                Text("Steps")
                    .foregroundStyle(imageSettings.customStepsEnabled ? .secondary : .primary)
                Spacer()
                Text("\(Int(imageSettings.steps))")
                    .font(.body.monospaced())
                    .foregroundStyle(imageSettings.customStepsEnabled ? .tertiary : .secondary)
            }
            CompactSlider(value: $imageSettings.steps, in: 1...20, step: 1)
#if os(iOS)
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
    private var seedSettingsSection: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $imageSettings.isSeedEnabled) {
                Text("Seed")
                    .foregroundStyle(imageSettings.isSeedEnabled ? .primary : .secondary)
            }
            HStack(alignment: .center) {
                TextField("Enter seed value", value: $imageSettings.seed, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                    .disabled(!imageSettings.isSeedEnabled)
                
                Stepper("Adjust seed value", value: $imageSettings.seed, in: -9007199254740991...9007199254740991)
                    .labelsHidden()
                    .disabled(!imageSettings.isSeedEnabled)
            }
            Text("Specifies the seed value used for image generation.")
                .font(.caption)
                .foregroundStyle(imageSettings.isSeedEnabled ? .secondary : .tertiary)
        }
    }
    
    @ViewBuilder
    private func keepAlivePicker(option: Binding<KeepAliveOption>, customValue: Binding<Int>, customUnit: Binding<KeepAliveUnit>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Keep Alive")
                Spacer()
                Picker("Keep Alive", selection: option) {
                    ForEach(KeepAliveOption.allCases) { opt in
                        Text(opt.localizedName).tag(opt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            
            if option.wrappedValue == .custom {
                HStack(alignment: .center) {
                    TextField("Enter Keep Alive Time", value: customValue, format: .number.grouping(.never))
                        .focused($isCustomKeepAliveFocused)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
#if os(iOS)
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
