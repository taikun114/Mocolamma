import SwiftUI

// MARK: - 設定ビュー

/// アプリケーションの「設定」ウィンドウのメインUIを定義するSwiftUIビューです。
/// 現時点ではプレースホルダーのコンテンツのみが含まれており、今後の機能追加のために用意されています。
struct SettingsView: View {
    var body: some View {
        // 設定ウィンドウのコンテンツはここに実装されます
        VStack {
            Text("General settings will go here.") // 一般設定はここに表示されます。
                .font(.title2)
                .foregroundColor(.secondary)
                .padding()
            Spacer() // コンテンツが上部に寄るようにSpacerを追加
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300) // 設定ウィンドウ全体の最小サイズ
        // 設定ウィンドウのタイトルはSettingsシーンで設定されるため、navigationTitleはここでは不要です
    }
}

// MARK: - プレビュー用

// 新しいプレビューマクロを使用
#Preview {
    SettingsView()
}
