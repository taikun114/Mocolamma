import SwiftUI

// MARK: - サーバー行ビュー

/// サーバーリストの個々の行を表すSwiftUIビューです。
/// サーバー名、ホスト、アイコン、および選択を示すチェックマークを表示します。
struct ServerRowView: View {
    let server: ServerInfo
    let isSelected: Bool // API通信用の選択状態
    let connectionStatus: ServerConnectionStatus? // nil: チェック中, .connected, .notConnected, .unknownHost

    var body: some View {
        HStack {
            // 接続状態を示すインジケーター
            Group {
                switch connectionStatus {
                case .connected:
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                case .notConnected, .unknownHost:
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                case .some(.errorWithMessage):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                case .checking, .none:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.trailing, 4) // アイコンとの間にスペースを追加

            // サーバーアイコン
            Image(systemName: "server.rack")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary) // アイコンの色はセカンダリカラーに設定

            VStack(alignment: .leading) { // テキストコンテンツをVStackでグループ化
                Text(server.name)
                    .font(.headline)
                    .lineLimit(1) // サーバー名を1行に収める
                    .truncationMode(.tail) // 末尾を省略
                    .help(server.name) // サーバー名のヘルプテキスト
                HStack {
                    Text(server.host)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1) // ホスト名を1行に収める
                        .truncationMode(.tail) // 末尾を省略
                        .help(server.host) // ホスト名のヘルプテキスト
                }
            }

            Spacer() // チェックマークを右に寄せる

            // サーバーがAPI通信用として選択されている場合のみチェックマークを表示
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3) // チェックマークのサイズを調整
                    .foregroundColor(.secondary) // チェックマークの色をセカンダリカラーに設定
            }
        }
        .padding(.vertical, 4) // 行に垂直方向のパディングを追加
    }
}

// MARK: - プレビュー

#Preview {
    ServerRowView(
        server: ServerInfo(name: "Local Server", host: "localhost:11434"),
        isSelected: true, // プレビュー用に選択状態を設定
        connectionStatus: .connected
    )
}

#Preview("Remote Selected") {
    ServerRowView(
        server: ServerInfo(name: "Remote Server", host: "192.168.1.100:11434"),
        isSelected: true, // プレビュー用に選択状態を設定
        connectionStatus: .notConnected(statusCode: 404)
    )
}

#Preview("Remote Unselected") {
    ServerRowView(
        server: ServerInfo(name: "Another Server", host: "api.example.com:11434"),
        isSelected: false, // プレビュー用に非選択状態を設定
        connectionStatus: .checking
    )
}

#Preview("Unknown Host") {
    ServerRowView(
        server: ServerInfo(name: "Unknown Host", host: "unknown.host:11434"),
        isSelected: false,
        connectionStatus: .unknownHost
    )
}
