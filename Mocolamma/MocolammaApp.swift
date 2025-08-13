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
    @State private var selection: String? = "server" // 状態変数をAppレベルに移動
    @State private var showingAboutSheet = false // Aboutシートの表示状態
    
    // インスペクターの表示状態を管理するStateをAppレベルに移動しました。
    // これにより、メニューコマンドから状態を操作できます。
    @State private var showingInspector: Bool = false

    // モデル追加シートの表示/非表示を制御するStateをAppレベルに移動
    @State private var showingAddModelsSheet = false

    // リフレッシュコマンドを発行するためのトリガー
    @StateObject private var appRefreshTrigger = RefreshTrigger()

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
                showingAddModelsSheet: $showingAddModelsSheet
            )
            #if os(macOS)
                .frame(minWidth: 500, minHeight: 300)
            #endif
                .environmentObject(appRefreshTrigger)
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
            // 標準のサイドバーコマンド（「サイドバーを切り替える」ボタン）を追加します。
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
                if selection == "server" { // サーバー画面が選択されている場合のみ表示
                    Button(action: {
                        showingAddModelsSheet = true
                    }) {
                        Label(String(localized: "Add Server…", comment: "サーバー追加メニューアイテム"), systemImage: "plus")
                    }
                    .keyboardShortcut("s", modifiers: [.option, .command])
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
                if selection == "server" { // サーバー画面が選択されている場合のみ表示
                    Button(action: {
                        showingAddModelsSheet = true
                    }) {
                        Label(String(localized: "Add Server…", comment: "サーバー追加メニューアイテム"), systemImage: "plus")
                    }
                    .keyboardShortcut("s", modifiers: [.option, .command])
                }
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
