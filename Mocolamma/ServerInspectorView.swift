
import SwiftUI
import AppKit // For NSPasteboard

struct ServerInspectorView: View {
    let server: ServerInfo
    let connectionStatus: Bool? // Can be nil while checking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name styled like the model name in the model inspector
            Text(server.name)
                .font(.title2)
                .bold()
                .padding(.bottom, 1) // Less padding

            // Connection status below the name in a secondary color
            if let status = connectionStatus {
                Text(status ? "Connection Status: Connected" : "Connection Status: Not Connected")
                    .font(.subheadline)
                    .foregroundColor(status ? .green : .secondary)
            } else {
                HStack(spacing: 4) {
                    Text("Connection Status: Checking...")
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
                    .font(.headline)
                Text(server.host)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.host, forType: .string)
                        }
                    }
            }

            Spacer()
        }
        .padding()
    }
}
