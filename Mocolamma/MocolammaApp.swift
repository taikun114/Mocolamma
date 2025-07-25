import SwiftUI

@main
struct MocolammaApp: App {
    var body: some Scene {
        // WindowGroup の初期化時に文字列を渡すことで、ウィンドウタイトルを設定します
        WindowGroup("Models") { // モデル
            ContentView()
        }
        .windowStyle(.titleBar) // 標準的なタイトルバーを使用します
        .windowToolbarStyle(.unifiedCompact) // ツールバーのスタイルをコンパクトにします
        .windowResizability(.contentMinSize) // ウィンドウの最小サイズをコンテンツに基づいて設定します
        .commands {
            // アプリケーションメニューのコマンドをカスタマイズしたい場合にここに記述します
        }
    }
}
