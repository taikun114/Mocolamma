import SwiftUI

struct RunningModelsCountView: View {
    @Environment(CommandExecutor.self) var commandExecutor
    let host: String
    let connectionStatus: ServerConnectionStatus?
    @State private var refreshID = UUID()
    @State private var runningModels: [OllamaRunningModel] = []
    @State private var isLoading: Bool = false
    @State private var expandedModelNames: Set<String> = []
    
    // 追加のプロパティ
    var showList: Bool = true
    var showSummary: Bool = true
    var externalModels: [OllamaRunningModel]? = nil
    var externalIsLoading = false
    var refreshAction: (() async -> Void)? = nil
    
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
        if isLoading || externalIsLoading {
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
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedModelNames.contains(model.name) },
                            set: { expanded in
                                if expanded { expandedModelNames.insert(model.name) }
                                else { expandedModelNames.remove(model.name) }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                if let backend = model.executionBackend {
                                    HStack(spacing: 4) {
                                        Text("Execution Backend:")
                                        Text(verbatim: backend)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                if let distribution = model.processorDistribution {
                                    HStack(spacing: 4) {
                                        Text("Allocation:")
                                        Text(verbatim: distribution)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if let formattedVRAMSize = model.formattedVRAMSize {
                                    Text("VRAM Size: \(formattedVRAMSize)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let contextLength = model.contextLength, contextLength > 0 {
                                    HStack(spacing: 4) {
                                        Text("Context Length:")
                                        Text(contextLength, format: .number)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if let expiresAt = model.expires_at {
                                    Text("Expires: \(expiresAt, formatter: Self.dateFormatter)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text(model.name)
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.primary)
                                .help(model.name)
                        }
                        .disclosureGroupStyle(RunningModelDisclosureStyle {
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
                        })
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
            expandedModelNames = []
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
        if let refreshAction {
            await refreshAction()
            return
        }
        let id = UUID()
        refreshID = id
        await MainActor.run {
            isLoading = true
            runningModels = []
        }
        let models = await commandExecutor.fetchRunningModels(host: host)
        guard !Task.isCancelled, refreshID == id else { return }
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

private struct RunningModelDisclosureStyle<Accessory: View>: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var accessory: () -> Accessory

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: configuration.isExpanded ? 4 : 0) {
            HStack(alignment: .center) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        configuration.label
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
                accessory()
            }
            VStack(alignment: .leading, spacing: 0) {
                if configuration.isExpanded {
                    configuration.content
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }
}

#Preview {
    RunningModelsCountView(host: "preview.invalid", connectionStatus: .connected,
                          externalModels: [
                            .init(name: "example-mixed:8b", expires_at: nil, size_vram: 3_000_000_000, size: 4_000_000_000),
                            .init(name: "example-gpu:8b", expires_at: nil, size_vram: 4_000_000_000, size: 4_000_000_000),
                            .init(name: "example-cpu:8b", expires_at: nil, size_vram: 0, size: 4_000_000_000)
                          ])
        .environment(CommandExecutor(serverManager: ServerManager()))
        .frame(width: 280)
        .padding()
}
