import SwiftUI
import Foundation
import CompactSlider

// MARK: - Inspector Content Helper View
struct InspectorContentView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    @Binding var selectedChatModelID: OllamaModel.ID?
    let sortedModels: [OllamaModel]
    let selectedServerForInspector: ServerInfo?
    @ObservedObject var serverManager: ServerManager
    @Binding var showingInspector: Bool
    @Binding var isChatStreamingEnabled: Bool
    @Binding var useCustomChatSettings: Bool
    @Binding var chatTemperature: Double
    
    @State private var modelInfo: [String: JSONValue]?
    @State private var licenseBody: String?
    @State private var licenseLink: String?
    @State private var isLoadingInfo: Bool = false
    @Binding var isTemperatureEnabled: Bool
    @Binding var isContextWindowEnabled: Bool
    @Binding var contextWindowValue: Double
    @Binding var isSystemPromptEnabled: Bool
    @Binding var systemPrompt: String
    @Binding var thinkingOption: ThinkingOption

    var body: some View {
        Group {
            if selection == "models" {
                if let selectedModelID = selectedModel,
                   let model = sortedModels.first(where: { $0.id == selectedModelID }) {
                    ModelInspectorDetailView(
                        model: model,
                        modelInfo: modelInfo,
                        isLoading: isLoadingInfo,
                        fetchedCapabilities: commandExecutor.selectedModelCapabilities,
                        licenseBody: licenseBody,
                        licenseLink: licenseLink
                    )
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
                    .id(UUID())
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
                        Toggle("Stream Response", isOn: $isChatStreamingEnabled)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Thinking", selection: $thinkingOption) {
                                ForEach(ThinkingOption.allCases) { option in
                                    Text(option.localizedName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(!(commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false))
                            .onChange(of: commandExecutor.selectedModelCapabilities) { _, caps in
                                let hasThinking = caps?.contains("thinking") ?? false
                                if !hasThinking { thinkingOption = .none }
                            }
                            Text("Specifies whether to perform inference when using a reasoning model.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Toggle(isOn: $isSystemPromptEnabled) {
                                Text("System Prompt")
                            }
                            TextEditor(text: $systemPrompt)
                                .frame(height: 100)
                                .disabled(!isSystemPromptEnabled)
                                .foregroundColor(isSystemPromptEnabled ? .primary : .secondary)
                                .scrollContentBackground(.hidden)
                                .background(isSystemPromptEnabled ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Section("Custom Settings") {
                        Toggle("Enable Custom Settings", isOn: $useCustomChatSettings)
                        
                        VStack {
                            Toggle(isOn: $isTemperatureEnabled) {
                                Text("Temperature")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $chatTemperature, in: 0.0...2.0, step: 0.1)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text(String(format: "%.1f", chatTemperature))
                                    .font(.body.monospaced())
                            }
                            .disabled(!isTemperatureEnabled)
                            .foregroundColor(isTemperatureEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!useCustomChatSettings)
                        .foregroundColor(useCustomChatSettings ? .primary : .secondary)

                        VStack {
                            Toggle(isOn: $isContextWindowEnabled) {
                                Text("Context Window")
                            }
                            .padding(.bottom, 4)
                            HStack {
                                CompactSlider(value: $contextWindowValue, in: 512...Double(commandExecutor.selectedModelContextLength ?? 4096), step: 128.0)
#if os(iOS)
                                    .frame(height: 32)
#else
                                    .frame(height: 16)
#endif
                                Text("\(Int(contextWindowValue))")
                                    .font(.body.monospaced())
                            }
                            .disabled(!isContextWindowEnabled)
                            .foregroundColor(isContextWindowEnabled ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!useCustomChatSettings)
                        .foregroundColor(useCustomChatSettings ? .primary : .secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 200)
            } else {
                Text("Nothing to display.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .id("nothing_to_display_placeholder")
                    .padding()
            }
        }
        .onChange(of: selectedModel) { _, newID in
            modelInfo = nil
            isLoadingInfo = true
            licenseBody = nil
            
            guard let newID = newID,
                  let model = sortedModels.first(where: { $0.id == newID }) else {
                isLoadingInfo = false
                return
            }
            
            Task {
                let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
                if selectedModel == newID {
                    await MainActor.run {
                        self.modelInfo = fetchedResponse?.model_info
                        self.licenseBody = fetchedResponse?.license
                        self.licenseLink = fetchedResponse?.model_info?["general.license.link"]?.stringValue
                        self.isLoadingInfo = false
                        let hasThinkingCapability = self.commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false
                        if !hasThinkingCapability {
                            self.thinkingOption = .none
                        }
                    }
                }
            }
        }
        .onChange(of: selectedChatModelID) { _, newID in
            modelInfo = nil
            isLoadingInfo = true
            licenseBody = nil
            
            guard let newID = newID,
                  let model = sortedModels.first(where: { $0.id == newID }) else {
                isLoadingInfo = false
                return
            }
            
            Task {
                let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
                if selectedChatModelID == newID {
                    await MainActor.run {
                        self.modelInfo = fetchedResponse?.model_info
                        self.licenseBody = fetchedResponse?.license
                        self.licenseLink = fetchedResponse?.model_info?["general.license.link"]?.stringValue
                        self.isLoadingInfo = false
                        let hasThinkingCapability = self.commandExecutor.selectedModelCapabilities?.contains("thinking") ?? false
                        if !hasThinkingCapability {
                            self.thinkingOption = .none
                        }
                    }
                }
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


