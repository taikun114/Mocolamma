import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ServerInspectorView: View {
    @Environment(CommandExecutor.self) var commandExecutor
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    let server: ServerInfo
    let connectionStatus: ServerConnectionStatus? // チェック中にnilになる可能性あり
    @State private var ollamaVersion: String? // Ollamaバージョン用の新しい状態変数
    @State private var versionHost: String?
    @State private var modelsState = ServerInspectorModelsState()
    @State private var versionRequestID = UUID()
    private let inspectorRefreshNotification = Notification.Name("InspectorRefreshRequested")
    
    private var indicatorSize: CGFloat {
#if !os(macOS)
        return 10
#else
        return 8
#endif
    }
    
    var body: some View {
        let copyIconName = SFSymbol.copy
        
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // モデルインスペクターのモデル名のようにスタイルされた名前
                Text(server.name)
                    .font(.title2)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(server.name)
                
                // 接続状態
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
                        if statusCode == -1004 {
                            Text("Not Connected (Connection failed)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not Connected (Status Code: \(statusCode))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
                            if statusCode == -1004 {
                                Text("Error (Connection failed)")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            } else {
                                Text("Error (Status Code: \(statusCode))")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
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
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(indicatorSize / 20)
                            .frame(width: indicatorSize, height: indicatorSize)
                        
                        Text("Checking...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                    .padding(.vertical, 5)
                
                // ホスト情報
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
                            Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(server.host, forType: .string)
#else
                                UIPasteboard.general.string = server.host
#endif
                            }
                        }
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Ollamaバージョン情報
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading) {
                        Text("Ollama Version:")
                            .font(.subheadline)
                        Text(displayedVersion)
                            .font(.title3)
                            .bold()
                            .foregroundColor(.primary)
                            .contextMenu {
                                Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(displayedVersion, forType: .string)
#else
                                    UIPasteboard.general.string = displayedVersion
#endif
                                }
                            }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Running Models:")
                            .font(.subheadline)
                        RunningModelsCountView(host: server.host, connectionStatus: connectionStatus, showList: false,
                                               externalModels: displayedModels, externalIsLoading: modelsState.isLoading || modelsState.host != server.host,
                                               refreshAction: refreshModels)
                            .environment(commandExecutor)
                    }

                    RunningModelsCountView(host: server.host, connectionStatus: connectionStatus, showSummary: false,
                                           externalModels: displayedModels, externalIsLoading: modelsState.isLoading || modelsState.host != server.host,
                                           refreshAction: refreshModels)
                        .environment(commandExecutor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: refreshContext) {
                    guard scenePhase == .active else {
                        modelsState.stop()
                        return
                    }
                    await modelsState.poll(host: server.host) { host in
                        await commandExecutor.fetchRunningModels(host: host)
                    }
                }
                .task(id: refreshContext) {
                    let request = UUID()
                    versionRequestID = request
                    guard scenePhase == .active else { return }
                    ollamaVersion = nil
                    versionHost = nil
                    await refreshVersion(request: request)
                }
                .onReceive(NotificationCenter.default.publisher(for: inspectorRefreshNotification)) { _ in
                    guard scenePhase == .active else { return }
                    let request = UUID()
                    versionRequestID = request
                    Task { await refreshVersion(request: request) }
                    Task { await refreshModels() }
                }
                .onDisappear {
                    modelsState.stop()
                    versionRequestID = UUID()
                }

                Spacer()
            }
            .padding()
        }
#if os(visionOS)
        .scrollClipDisabled()
#endif
    }

    private struct RefreshContext: Equatable {
        let serverID: ServerInfo.ID
        let host: String
        let isActive: Bool
    }

    private var refreshContext: RefreshContext {
        .init(serverID: server.id, host: server.host, isActive: scenePhase == .active)
    }

    private func refreshModels() async {
        await modelsState.refresh(host: server.host) { host in
            await commandExecutor.fetchRunningModels(host: host)
        }
    }

    private var displayedVersion: String {
        versionHost == server.host ? (ollamaVersion ?? "-") : "-"
    }

    private var displayedModels: [OllamaRunningModel] {
        modelsState.host == server.host ? modelsState.models : []
    }

    private func refreshVersion(request: UUID) async {
        guard !Task.isCancelled, versionRequestID == request else { return }
        do {
            let version = try await commandExecutor.fetchOllamaVersion(host: server.host)
            guard !Task.isCancelled, versionRequestID == request else { return }
            versionHost = server.host
            ollamaVersion = version
        } catch {
            guard !Task.isCancelled, versionRequestID == request else { return }
            versionHost = server.host
            ollamaVersion = "-"
            print("Error fetching Ollama version: \(error)")
        }
    }

}
