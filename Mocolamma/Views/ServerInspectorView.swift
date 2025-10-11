import SwiftUI
#if os(macOS)
import AppKit // For NSPasteboard
#endif

struct ServerInspectorView: View {
    @EnvironmentObject var commandExecutor: CommandExecutor
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    let server: ServerInfo
    let connectionStatus: ServerConnectionStatus? // Can be nil while checking
    @State private var ollamaVersion: String? // New state variable for Ollama version
    private let inspectorRefreshNotification = Notification.Name("InspectorRefreshRequested")

    private var indicatorSize: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 8
        #endif
    }

    var body: some View {
        ScrollView { // ScrollViewを追加
            VStack(alignment: .leading, spacing: 10) {
                // Name styled like the model name in the model inspector
                Text(server.name)
                    .font(.title2)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(server.name)

                // Connection status
                switch connectionStatus {
                case .connected:
                    HStack(spacing: 4) {
                        if differentiateWithoutColor {
                            Image(systemName: "checkmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: indicatorSize, height: indicatorSize)
                                .foregroundColor(.green)
                                .fontWeight(.bold)
                        } else {
                            Circle().fill(.green).frame(width: indicatorSize, height: indicatorSize)
                        }
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                case .notConnected(let statusCode):
                    HStack(spacing: 4) {
                        if differentiateWithoutColor {
                            Image(systemName: "xmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: indicatorSize, height: indicatorSize)
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                        } else {
                            Circle().fill(.red).frame(width: indicatorSize, height: indicatorSize)
                        }
                        Text("Not Connected (Status Code: \(statusCode))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                case .errorWithMessage(let statusCode, let errorMessage):
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if differentiateWithoutColor {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: indicatorSize, height: indicatorSize)
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: indicatorSize, height: indicatorSize)
                                    .foregroundColor(.orange)
                            }
                            Text("Error (Status Code: \(statusCode))")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                case .unknownHost:
                    HStack(spacing: 4) {
                        if differentiateWithoutColor {
                            Image(systemName: "xmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: indicatorSize, height: indicatorSize)
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                        } else {
                            Circle().fill(.red).frame(width: indicatorSize, height: indicatorSize)
                        }
                        Text("Not Connected (Unknown Host)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                case .timedOut:
                    HStack(spacing: 4) {
                        if differentiateWithoutColor {
                            Image(systemName: "xmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: indicatorSize, height: indicatorSize)
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                        } else {
                            Circle().fill(.red).frame(width: indicatorSize, height: indicatorSize)
                        }
                        Text("Not Connected (Timeout)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                case .checking, .none:
                    HStack(spacing: 4) {
                        if differentiateWithoutColor {
                            Image(systemName: "questionmark.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: indicatorSize, height: indicatorSize)
                                .foregroundColor(.gray)
                                .fontWeight(.bold)
                        } else {
                            Circle().fill(.gray).frame(width: indicatorSize, height: indicatorSize)
                        }
                        Text("Checking...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !differentiateWithoutColor {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        }
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
                            Button("Copy", systemImage: "document.on.document") {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(server.host, forType: .string)
                                #else
                                UIPasteboard.general.string = server.host
                                #endif
                            }
                        }                
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Ollama Version information
                VStack(alignment: .leading, spacing: 10) { // Changed spacing from 6 to 10
                    VStack(alignment: .leading) {
                        Text("Ollama Version:")
                            .font(.subheadline)
                        Text(ollamaVersion ?? "-")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.primary)
                             .contextMenu {
                                Button("Copy", systemImage: "document.on.document") {
                                    #if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(ollamaVersion ?? "-", forType: .string)
                                    #else
                                    UIPasteboard.general.string = ollamaVersion ?? "-"
                                    #endif
                                }
                            }                    
                    }
                    VStack(alignment: .leading) {
                        Text("Running Models:")
                            .font(.subheadline)
                                                RunningModelsCountView(host: server.host, connectionStatus: connectionStatus)
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