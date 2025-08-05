import SwiftUI

struct RunningModelsCountView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let host: String
    @State private var countText: String = "-"
    @State private var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().scaleEffect(0.6)
            }
            Text(countText)
                .font(.title3)
                .bold()
                .foregroundColor(.primary)
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
            countText = "-"
        }
        let count = await commandExecutor.fetchRunningModelsCount(host: host)
        await MainActor.run {
            if let c = count {
                countText = String(c)
            } else {
                countText = "-"
            }
            isLoading = false
        }
    }
}

#Preview {
    RunningModelsCountView(host: "localhost:11434")
        .environmentObject(CommandExecutor(serverManager: ServerManager()))
        .frame(width: 200)
        .padding()
}
