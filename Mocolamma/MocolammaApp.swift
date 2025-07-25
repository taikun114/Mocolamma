import SwiftUI

@main
struct MocolammaApp: App {
    var body: some Scene {
        // WindowGroup の初期化時に文字列を渡すことで、ウィンドウタイトルを設定
        WindowGroup("モデル") {
            ContentView()
        }
        .windowStyle(.titleBar) // 標準的なタイトルバーを使用
        .windowToolbarStyle(.unifiedCompact) // ツールバーのスタイルをコンパクトに
        .windowResizability(.contentMinSize) // ウィンドウの最小サイズをコンテンツに基づいて設定
        .commands {
            // アプリケーションメニューのコマンドをカスタマイズしたい場合にここに記述
        }
    }
}
