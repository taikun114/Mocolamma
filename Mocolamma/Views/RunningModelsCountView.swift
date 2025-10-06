import SwiftUI

struct RunningModelsCountView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let host: String
    let connectionStatus: ServerConnectionStatus? // Add connectionStatus
    @State private var runningModels: [OllamaRunningModel] = []
    @State private var isLoading: Bool = false
    @State private var isExpanded: Bool = false

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
                return String(runningModels.count)
            } else {
                return "-"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .bottom, spacing: 4) { // Added alignment: .bottom
                Text(displayCountText)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.primary)
                Text("running")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)
            }

            if runningModels.count > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(runningModels, id: \.name) { model in
                        VStack(alignment: .leading) {
                            Text(model.name) // Model name, bold
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.primary) // Changed to primary for bold text

                            if let formattedVRAMSize = model.formattedVRAMSize { // Add VRAM size
                                Text("VRAM Size: \(formattedVRAMSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let expiresAt = model.expires_at {
                                Text("Expires: \(expiresAt, formatter: Self.dateFormatter)") // Expires date, not bold
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: host) {
            await refresh()
        }
        .contextMenu {
            Button("Refresh") {
                Task { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InspectorRefreshRequested"))) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await MainActor.run {
            isLoading = true
            runningModels = [] // Clear previous models
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
    RunningModelsCountView(host: "localhost:11434", connectionStatus: .connected) // Added connectionStatus for preview
        .environmentObject(CommandExecutor(serverManager: ServerManager()))
        .frame(width: 200)
        .padding()
}
