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
    @State private var selection: String? = "server" // 状態変数をAppレベルに移動
    @State private var showingAboutSheet = false // Aboutシートの表示状態

    var body: some Scene {
        WindowGroup() {
            // ContentViewにServerManagerとselectionのBindingを渡します
            ContentView(serverManager: serverManager, selection: $selection)
                .sheet(isPresented: $showingAboutSheet) {
                    AboutView()
                }
        }
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .appInfo) {
                 Button("About Mocolamma") {
                     openWindow(id: "about-window")
                 }
            }
            #else
            // iPadOSの場合、設定メニュー項目を置き換えてアプリ内設定を開く
            CommandGroup(replacing: .appSettings) {
                Button(action: {
                    showingAboutSheet = true
                }) {
                    Label("About Mocolamma…", systemImage: "info.circle")
                }
                Divider()
                Button(action: {
                    selection = "settings"
                }) {
                    Label(String(localized: "Settings…", comment: "設定メニューアイテム"), systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
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

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
