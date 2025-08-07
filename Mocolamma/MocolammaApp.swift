import SwiftUI

// MARK: - メインアプリケーション構造

/// アプリケーションの起動ポイントとなる基本ファイルです。
/// ウィンドウのタイトルやスタイルなどの初期設定を行い、
/// アプリケーションのメインコンテンツビューであるContentViewをホストします。
@main
struct MocolammaApp: App {
    @Environment(\.openWindow) private var openWindow
    // アプリケーション全体で共有されるServerManagerのインスタンスを作成します。
    // @StateObject を使用することで、アプリのライフサイクル全体でインスタンスが保持されます。
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        WindowGroup() {
            // ContentViewにServerManagerのインスタンスを渡します
            ContentView(serverManager: serverManager)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commandsReplaced(content: {
            CommandGroup(replacing: .appInfo, addition: {
                 Button("About Mocolamma") {
                     openWindow(id: "about-window")
                 }
            })
        })
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }

        Window("About Mocolamma", id: "about-window") {
            AboutView()
        }
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
        #endif
    }
}
