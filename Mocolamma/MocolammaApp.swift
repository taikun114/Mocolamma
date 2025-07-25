import SwiftUI

@main
struct MocolammaApp: App {
    var body: some Scene {
        // WindowGroup の初期化時に文字列を渡すことで、ウィンドウタイトルを設定します
        WindowGroup("Models") { // モデル
            ContentView()
        }
        .windowStyle(.titleBar) // 標準的なタイトルバーを使用します
        .windowResizability(.contentMinSize) // ウィンドウの最小サイズをコンテンツに基づいて設定します
        .commands {
            // アプリケーションメニューのコマンドをカスタマイズしたい場合にここに記述します
            // Settings シーンが自動的に「Settings...」メニュー項目を提供するので、
            // ここでCommandGroup(replacing: .appSettings)は不要になります。
        }

        // macOSアプリの設定ウィンドウには、専用のSettingsシーンを使用します。
        // これにより、自動的にアプリケーションメニューに「設定...」項目が追加されます。
        Settings {
            SettingsView()
        }
    }
}
