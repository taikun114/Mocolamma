import SwiftUI

// MARK: - サーバー行ビュー

/// サーバーリストの個々の行を表すSwiftUIビューです。
/// サーバー名、ホスト、アイコン、および選択を示すチェックマークを表示します。
struct ServerRowView: View {
    let server: ServerInfo
    let isSelected: Bool // API通信用の選択状態
    let connectionStatus: Bool? // nil: チェック中, true: 接続済み, false: 未接続

    var body: some View {
        HStack {
            // 接続状態を示す丸い図形
            Group {
                if let status = connectionStatus {
                    Circle()
                        .fill(status ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                } else {
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
                HStack {
                    Text(server.host)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
        // listRowBackgroundとcontextMenuはServerViewで適用されます。
    }
}

// MARK: - プレビュー

#Preview {
    ServerRowView(
        server: ServerInfo(name: "Local Server", host: "localhost:11434"),
        isSelected: true, // プレビュー用に選択状態を設定
        connectionStatus: true
    )
}

#Preview("Remote Selected") {
    ServerRowView(
        server: ServerInfo(name: "Remote Server", host: "192.168.1.100:11434"),
        isSelected: true, // プレビュー用に選択状態を設定
        connectionStatus: false
    )
}

#Preview("Remote Unselected") {
    ServerRowView(
        server: ServerInfo(name: "Another Server", host: "api.example.com:11434"),
        isSelected: false, // プレビュー用に非選択状態を設定
        connectionStatus: nil
    )
}
