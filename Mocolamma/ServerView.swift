import SwiftUI

// MARK: - サーバービュー

/// アプリケーションのメインサイドバーからアクセスされるサーバーコンテンツのUIを定義するSwiftUIビューです。
/// 現時点ではプレースホルダーのコンテンツのみが含まれており、今後の機能追加のために用意されています。
struct ServerView: View {
    var body: some View {
        VStack {
            Text("Server content will go here.") // サーバーのコンテンツはここに表示されます。
                .font(.title2)
                .foregroundColor(.secondary)
                .padding()
            Spacer() // コンテンツが上部に寄るようにSpacerを追加
        }
        .navigationTitle("Server") // ナビゲーションタイトル: サーバー。
        .padding()
    }
}

// MARK: - プレビュー用

// 新しいプレビューマクロを使用
#Preview {
    ServerView()
}
