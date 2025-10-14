import SwiftUI
import Combine

// MARK: - メインアプリケーション構造

/// アプリケーションの起動ポイントとなる基本ファイルです。
/// ウィンドウのタイトルやスタイルなどの初期設定を行い、
/// アプリケーションのメインコンテンツビューであるContentViewをホストします。
#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct MocolammaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @Environment(\.openWindow) private var openWindow
    // アプリケーション全体で共有されるServerManagerのインスタンスを作成します。
    // @StateObject を使用することで、アプリのライフサイクル全体でインスタンスが保持されます。
    @StateObject private var serverManager = ServerManager()
    @StateObject private var localNetworkChecker = LocalNetworkPermissionChecker()
    @State private var selection: String? = "server"
    @State private var showingAboutSheet = false // Aboutシートの表示状態
    @State private var showingAddModelsSheet = false
    @State private var showingAddServerSheet = false
    @State private var showingInspector: Bool = false

    // リフレッシュコマンドを発行するためのトリガー
    @StateObject private var appRefreshTrigger = RefreshTrigger()
    
    // チャットクリア要求を伝える状態変数
    @State private var shouldClearChat: Bool = false
    
    // ダウンロード状態を伝える状態変数
    @State private var isPulling: Bool = false

    // メニュー項目の有効/無効を判断する計算プロパティ
    private var isMenuActionDisabled: Bool {
        switch selection {
        case "server", "models", "chat": // サーバー、モデル、チャットのいずれかの画面が開いている場合は有効
            return false
        default: // "settings" または nil (初期状態など) の場合は無効
            return true
        }
    }

#if os(macOS)
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false  // これでタブ機能無効化 & メニュー項目非表示
    }
#endif

    var body: some Scene {
        WindowGroup() {
            // ContentViewにrefreshTriggerのPublisherを渡します。
            ContentView(
                serverManager: serverManager,
                selection: $selection,
                showingInspector: $showingInspector,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingAddServerSheet: $showingAddServerSheet,
                shouldClearChat: $shouldClearChat,
                isPulling: $isPulling
            )
            #if os(macOS)
                .frame(minWidth: 1000, minHeight: 500)
            #endif
                .environmentObject(appRefreshTrigger)
                .onAppear {
                    localNetworkChecker.refresh()
                }
                .sheet(isPresented: $showingAboutSheet) {
                    AboutView()
                }
        }
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .appInfo) {
                Button(action: {
                    openWindow(id: "about-window")
                }) {
                    Label("About Mocolamma", systemImage: "info.circle")
                }
            }
            SidebarCommands()
            InspectorCommands()

            // リフレッシュコマンドを表示メニューの先頭に追加
            CommandGroup(before: .sidebar) {
                Button(action: {
                    appRefreshTrigger.send()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isMenuActionDisabled) // ここで無効化を適用
                Divider()
            }

            CommandGroup(replacing: .newItem) { // 新規ウィンドウのメニュー/ショートカットを無効化
                Button(action: {
                    showingAddServerSheet = true
                }) {
                    Label(String(localized: "Add Server…"), systemImage: "plus")
                }
                .keyboardShortcut("s", modifiers: [.option, .command])
                .disabled(selection != "server")

                Button(action: {
                    showingAddModelsSheet = true
                }) {
                    Label(String(localized: "Add Model…"), systemImage: "plus")
                }
                .keyboardShortcut("m", modifiers: [.option, .command])
                .disabled(selection != "models" || isPulling)
                
                Button(action: {
                    // チャットクリア要求を設定
                    shouldClearChat = true
                }) {
                    Label(String(localized: "New Chat"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.option, .command])
                .disabled(selection != "chat")
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
                    Label(String(localized: "Settings…"), systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            SidebarCommands()
            InspectorCommands()

            // リフレッシュコマンドを表示メニューの先頭に追加（iPadOS）
            CommandGroup(before: .sidebar) {
                Button(action: {
                    appRefreshTrigger.send()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isMenuActionDisabled) // ここで無効化を適用
                Divider()
            }

            // iPadOSでも「サーバーを追加」メニュー項目を追加
            CommandGroup(after: .newItem) { // 新規ウィンドウのメニュー/ショートカットを無効化
                Button(action: {
                    showingAddServerSheet = true
                }) {
                    Label(String(localized: "Add Server…"), systemImage: "plus")
                }
                .keyboardShortcut("s", modifiers: [.option, .command])
                .disabled(selection != "server")

                Button(action: {
                    showingAddModelsSheet = true
                }) {
                    Label(String(localized: "Add Model…"), systemImage: "plus")
                }
                .keyboardShortcut("m", modifiers: [.option, .command])
                .disabled(selection != "models" || isPulling)
                
                Button(action: {
                    // チャットクリア要求を設定
                    shouldClearChat = true
                }) {
                    Label(String(localized: "New Chat"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.option, .command])
                .disabled(selection != "chat")
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 600)
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
