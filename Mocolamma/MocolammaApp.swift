import SwiftUI

// MARK: - View Commands

/// 表示メニューのカスタマイズを管理します。
struct ViewCommands: Commands {
    /// Inspectorの表示/非表示を制御するためのBinding。
    @Binding var showingInspector: Bool

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(action: {
                showingInspector.toggle()
            }) {
                Label(showingInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}


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
    
    // インスペクターの表示状態を管理するStateをAppレベルに移動しました。
    // これにより、メニューコマンドから状態を操作できます。
    @State private var showingInspector: Bool = false

#if os(macOS)
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false  // これでタブ機能無効化 & メニュー項目非表示
    }
#endif

    var body: some Scene {
        WindowGroup() {
            // ContentViewにshowingInspectorのBindingを渡します。
            ContentView(serverManager: serverManager, selection: $selection, showingInspector: $showingInspector)
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
            // 標準のサイドバーコマンド（「サイドバーを切り替える」ボタン）を追加します。
            SidebarCommands()

            CommandGroup(replacing: .newItem) {}  // 新規ウィンドウのメニュー/ショートカットを無効化

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
            SidebarCommands()
            #endif
            
            // カスタマイズされた表示メニューコマンドを追加します。
            ViewCommands(showingInspector: $showingInspector)
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
