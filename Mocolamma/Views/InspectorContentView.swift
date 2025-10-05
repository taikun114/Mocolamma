import SwiftUI
import Foundation
import CompactSlider

// MARK: - Inspector Content Helper View
struct InspectorContentView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    @EnvironmentObject var chatSettings: ChatSettings
    let selection: String?
    @Binding var selectedModel: OllamaModel.ID?
    let sortedModels: [OllamaModel]
    let selectedServerForInspector: ServerInfo?
    @ObservedObject var serverManager: ServerManager
    @Binding var showingInspector: Bool

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
                        Toggle("Stream Response", isOn: $chatSettings.isStreamingEnabled)
                        
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
                                .frame(height: 100)
                                .disabled(!chatSettings.isSystemPromptEnabled)
                                .foregroundColor(chatSettings.isSystemPromptEnabled ? .primary : .secondary)
                                .scrollContentBackground(.hidden)
                                .background(chatSettings.isSystemPromptEnabled ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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
