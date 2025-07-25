import SwiftUI

// MARK: - サーバー行ビュー

/// サーバーリストの個々の行を表すSwiftUIビューです。
/// サーバー名、ホスト、アイコン、および選択を示すチェックマークを表示します。
struct ServerRowView: View {
    let server: ServerInfo
    let isSelected: Bool // API通信用の選択状態

    var body: some View {
        HStack {
            // サーバーアイコン
            Image(systemName: "server.rack")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary) // アイコンの色はセカンダリカラーに設定

            VStack(alignment: .leading) { // テキストコンテンツをVStackでグループ化
                Text(server.name)
                    .font(.headline)
                Text(server.host)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
        isSelected: true // プレビュー用に選択状態を設定
    )
}

#Preview("Remote Selected") {
    ServerRowView(
        server: ServerInfo(name: "Remote Server", host: "192.168.1.100:11434"),
        isSelected: true // プレビュー用に選択状態を設定
    )
}

#Preview("Remote Unselected") {
    ServerRowView(
        server: ServerInfo(name: "Another Server", host: "api.example.com:11434"),
        isSelected: false // プレビュー用に非選択状態を設定
    )
}
