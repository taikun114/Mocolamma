import SwiftUI

// MARK: - サーバーインスペクター詳細ビューヘルパー
struct ServerInspectorDetailView: View {
    let server: ServerInfo
    let connectionStatus: ServerConnectionStatus?

    var body: some View {
        ServerInspectorView(
            server: server,
            connectionStatus: connectionStatus
        )
    }
}
