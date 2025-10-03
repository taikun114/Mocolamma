import SwiftUI

// MARK: - Server Inspector Detail View Helper
struct ServerInspectorDetailView: View {
    let server: ServerInfo
    let connectionStatus: Bool?

    var body: some View {
        ServerInspectorView(
            server: server,
            connectionStatus: connectionStatus
        )
    }
}
