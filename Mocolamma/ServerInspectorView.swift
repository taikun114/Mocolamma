import SwiftUI
import AppKit // For NSPasteboard

struct ServerInspectorView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    let server: ServerInfo
    let connectionStatus: Bool? // Can be nil while checking
    @State private var ollamaVersion: String? // New state variable for Ollama version
    private let inspectorRefreshNotification = Notification.Name("InspectorRefreshRequested")

    var body: some View {
        ScrollView { // ScrollViewを追加
            VStack(alignment: .leading, spacing: 10) {
                // Name styled like the model name in the model inspector
                Text(server.name)
                    .font(.title2)
                    .bold()

                // Connection status below the name in a secondary color
                if let status = connectionStatus {
                    HStack(spacing: 4) { // HStackで囲む
                        Circle() // インジケーターの追加
                            .fill(status ? .green : .red) // 接続状況に応じて色を変更
                            .frame(width: 8, height: 8) // サイズ調整
                        Text(status ? "Connected" : "Not Connected")
                            .font(.subheadline)
                            .foregroundColor(status ? .green : .secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle() // インジケーターの追加
                            .fill(.gray) // Checking中は灰色
                            .frame(width: 8, height: 8) // サイズ調整
                        Text("Checking...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    }
                }

                Divider()
                    .padding(.vertical, 5)

                // Host information
                VStack(alignment: .leading) {
                    Text("Host:")
                        .font(.subheadline)
                    Text(server.host)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(server.host)
                        .foregroundColor(.primary)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(server.host, forType: .string)
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Ollama Version information
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading) {
                        Text("Ollama Version:")
                            .font(.subheadline)
                        Text(ollamaVersion ?? "-")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.primary)
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(ollamaVersion ?? "-", forType: .string)
                                }
                            }
                    }
                    VStack(alignment: .leading) {
                        Text("Running Models:")
                            .font(.subheadline)
                        RunningModelsCountView(host: server.host)
                            .environmentObject(commandExecutor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: server.host) {
                    do {
                        ollamaVersion = try await commandExecutor.fetchOllamaVersion(host: server.host)
                    } catch {
                        ollamaVersion = "-"
                        print("Error fetching Ollama version: \(error)")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: inspectorRefreshNotification)) { _ in
                    Task {
                        do {
                            ollamaVersion = try await commandExecutor.fetchOllamaVersion(host: server.host)
                        } catch {
                            ollamaVersion = "-"
                            print("Error fetching Ollama version (refresh): \(error)")
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}