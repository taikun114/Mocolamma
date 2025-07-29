import SwiftUI

// MARK: - メインアプリケーション構造

/// アプリケーションの起動ポイントとなる基本ファイルです。
/// ウィンドウのタイトルやスタイルなどの初期設定を行い、
/// アプリケーションのメインコンテンツビューであるContentViewをホストします。
@main
struct MocolammaApp: App {
    // アプリケーション全体で共有されるServerManagerのインスタンスを作成します。
    // @StateObject を使用することで、アプリのライフサイクル全体でインスタンスが保持されます。
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        WindowGroup() {
            // ContentViewにServerManagerのインスタンスを渡します
            ContentView(serverManager: serverManager)
        }
        .windowStyle(.titleBar) // 標準的なタイトルバーを使用します
        .windowResizability(.contentMinSize) // ウィンドウの最小サイズをコンテンツに基づいて設定します
        
        // 設定ウィンドウを定義します。macOSの標準的な「設定...」メニュー項目を自動で提供します。
        Settings {
            SettingsView()
        }
    }
}
