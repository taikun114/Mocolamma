import SwiftUI
import Foundation
import CompactSlider

// MARK: - インスペクターコンテンツヘルパービュー
struct InspectorContentView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
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
                        VStack(alignment: .leading) {
                            Toggle("Stream Response", isOn: $chatSettings.isStreamingEnabled)
                            Text("If you turn off stream response, it is recommended to set the API timeout to unlimited in the settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
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
                }
#endif
            } else if selection == "image_generation" {
                Form {
                    Section("Image Generation Settings") {
                        VStack(alignment: .leading) {
                            Toggle("Stream Response", isOn: $imageSettings.isStreamingEnabled)
                            Text("If you turn off stream response, it is recommended to set the API timeout to unlimited in the settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Width")
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customWidthEnabled) ? .secondary : .primary)
                                Spacer()
                                Text("\(Int(imageSettings.width)) px")
                                    .font(.body.monospaced())
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customWidthEnabled) ? .tertiary : .secondary)
                            }
                            CompactSlider(value: $imageSettings.width, in: 64...2048, step: 64)
#if os(iOS)
                                .frame(height: 32)
#else
                                .frame(height: 16)
#endif
                                .disabled(imageSettings.useCustomSettings && imageSettings.customWidthEnabled)
                            Text("Specifies the width of the image you want to generate.")
                                .font(.caption)
                                .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customWidthEnabled) ? .tertiary : .secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Height")
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customHeightEnabled) ? .secondary : .primary)
                                Spacer()
                                Text("\(Int(imageSettings.height)) px")
                                    .font(.body.monospaced())
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customHeightEnabled) ? .tertiary : .secondary)
                            }
                            CompactSlider(value: $imageSettings.height, in: 64...2048, step: 64)
#if os(iOS)
                                .frame(height: 32)
#else
                                .frame(height: 16)
#endif
                                .disabled(imageSettings.useCustomSettings && imageSettings.customHeightEnabled)
                            Text("Specifies the height of the image you want to generate.")
                                .font(.caption)
                                .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customHeightEnabled) ? .tertiary : .secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Steps")
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customStepsEnabled) ? .secondary : .primary)
                                Spacer()
                                Text("\(Int(imageSettings.steps))")
                                    .font(.body.monospaced())
                                    .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customStepsEnabled) ? .tertiary : .secondary)
                            }
                            CompactSlider(value: $imageSettings.steps, in: 1...100, step: 1)
#if os(iOS)
                                .frame(height: 32)
#else
                                .frame(height: 16)
#endif
                                .disabled(imageSettings.useCustomSettings && imageSettings.customStepsEnabled)
                            Text("Specifies the number of image generation steps. Increasing the number of steps increases generation time but can improve detail.")
                                .font(.caption)
                                .foregroundStyle((imageSettings.useCustomSettings && imageSettings.customStepsEnabled) ? .tertiary : .secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.isSeedEnabled) {
                                Text("Seed")
                                    .foregroundStyle(imageSettings.isSeedEnabled ? .primary : .secondary)
                            }
                            HStack {
                                TextField("Enter seed value", value: $imageSettings.seed, format: .number.grouping(.never))
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
#if os(iOS)
                                    .keyboardType(.numberPad)
#endif
                                    .disabled(!imageSettings.isSeedEnabled)
                                
                                Stepper("Adjust seed value", value: $imageSettings.seed)
                                    .labelsHidden()
                                    .disabled(!imageSettings.isSeedEnabled)
                            }
                            Text("Specifies the seed value used for image generation.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.isSeedEnabled ? .secondary : .tertiary)
                        }
                    }
                    
                    Section("Custom Settings") {
                        Toggle("Enable Custom Settings", isOn: $imageSettings.useCustomSettings)
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customWidthEnabled) {
                                Text("Custom Width")
                                    .foregroundStyle(imageSettings.useCustomSettings ? .primary : .secondary)
                            }
                            TextField("Enter custom width", text: $imageSettings.customWidth)
                                .focused($isCustomWidthFocused)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                                .disabled(!imageSettings.customWidthEnabled)
                            Text("Enter the desired image width as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.useCustomSettings ? .secondary : .tertiary)
                        }
                        .disabled(!imageSettings.useCustomSettings)
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customHeightEnabled) {
                                Text("Custom Height")
                                    .foregroundStyle(imageSettings.useCustomSettings ? .primary : .secondary)
                            }
                            TextField("Enter custom height", text: $imageSettings.customHeight)
                                .focused($isCustomHeightFocused)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                                .disabled(!imageSettings.customHeightEnabled)
                            Text("Enter the desired image height as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.useCustomSettings ? .secondary : .tertiary)
                        }
                        .disabled(!imageSettings.useCustomSettings)
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $imageSettings.customStepsEnabled) {
                                Text("Custom Steps")
                                    .foregroundStyle(imageSettings.useCustomSettings ? .primary : .secondary)
                            }
                            TextField("Enter custom steps", text: $imageSettings.customSteps)
                                .focused($isCustomStepsFocused)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                                .disabled(!imageSettings.customStepsEnabled)
                            Text("Enter the number of image generation steps as a number to override the above setting and manually specify the size.")
                                .font(.caption)
                                .foregroundStyle(imageSettings.useCustomSettings ? .secondary : .tertiary)
                        }
                        .disabled(!imageSettings.useCustomSettings)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
#if os(iOS)
                .onTapGesture {
                    isCustomWidthFocused = false
                    isCustomHeightFocused = false
                    isCustomStepsFocused = false
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
}
