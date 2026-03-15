import SwiftUI

struct RunningModelsCountView: View {
    @Environment(CommandExecutor.self) var commandExecutor
    let host: String
    let connectionStatus: ServerConnectionStatus?
    @State private var runningModels: [OllamaRunningModel] = []
    @State private var isLoading: Bool = false
    @State private var isExpanded: Bool = false
    
    // 追加のプロパティ
    var showList: Bool = true
    var showSummary: Bool = true
    var externalModels: [OllamaRunningModel]? = nil
    
    private var currentModels: [OllamaRunningModel] {
        externalModels ?? runningModels
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private var displayCountText: String {
        if isLoading {
            return "-"
        } else {
            if case .connected = connectionStatus {
                return String(currentModels.count)
            } else {
                return "-"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if showSummary {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(displayCountText)
                        .font(.title3)
                        .bold()
                        .foregroundColor(.primary)
                    Text("running")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                }
            }
            
            if showList && currentModels.count > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(currentModels.enumerated()), id: \.element.name) { index, model in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .help(model.name)
                                
                                if let formattedVRAMSize = model.formattedVRAMSize {
                                    Text("VRAM Size: \(formattedVRAMSize)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let expiresAt = model.expires_at {
                                    Text("Expires: \(expiresAt, formatter: Self.dateFormatter)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    await commandExecutor.unloadModel(modelName: model.name, host: host)
                                }
                            }) {
#if os(visionOS)
                                Label("Unload", systemImage: "tray.and.arrow.up")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 20, height: 20)
#else
                                Image(systemName: "tray.and.arrow.up")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20, height: 20)
#endif
                            }
#if os(visionOS)
                            .buttonStyle(.bordered)
#else
                            .buttonStyle(.plain)
#endif
                            .help("Unload this model from memory.")
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(action: {
                                Task {
                                    await commandExecutor.unloadModel(modelName: model.name, host: host)
                                }
                            }) {
                                Label("Unload", systemImage: "tray.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                Task { await refresh() }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        
                        if index < currentModels.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: host) {
            if externalModels == nil {
                await refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InspectorRefreshRequested"))) { _ in
            if externalModels == nil {
                Task { await refresh() }
            }
        }
    }
    
    private func refresh() async {
        await MainActor.run {
            isLoading = true
            runningModels = []
        }
        let models = await commandExecutor.fetchRunningModels(host: host)
        await MainActor.run {
            if let m = models {
                runningModels = m
            } else {
                runningModels = []
            }
            isLoading = false
        }
    }
}

#Preview {
    RunningModelsCountView(host: "localhost:11434", connectionStatus: .connected)
        .environment(CommandExecutor(serverManager: ServerManager()))
        .frame(width: 200)
        .padding()
}
