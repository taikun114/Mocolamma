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
    @Environment(\.dismissWindow) private var dismissWindow
    
    // アプリケーション全体で共有されるServerManagerのインスタンスを作成します。
    // @StateObject を使用することで、アプリのライフサイクル全体でインスタンスが保持されます。
    @State private var serverManager = ServerManager()
    @State private var localNetworkChecker = LocalNetworkPermissionChecker()
    @State private var imageSettings = ImageGenerationSettings()
    @State private var chatSettings = ChatSettings() // ContentViewから昇格させて共有
    @State private var executor: CommandExecutor
    @State private var selection: String? = "server"
    @State private var showingAboutSheet = false // Aboutシートの表示状態
    @State private var showingAddModelsSheet = false
    @State private var showingAddServerSheet = false
    @State private var showingInspector: Bool = false
    
    // リフレッシュコマンドを発行するためのトリガー
    @State private var appRefreshTrigger = RefreshTrigger()
    
    // チャットクリア要求を伝える状態変数
    @State private var shouldClearChat: Bool = false
    @State private var shouldClearGeneration: Bool = false
    
    // ダウンロード状態を伝える状態変数
    @State private var isPulling: Bool = false
    
    // メニュー項目の有効/無効を判断する計算プロパティ
    private var isMenuActionDisabled: Bool {
        switch selection {
        case "server", "models", "chat", "image_generation": // サーバー、モデル、チャット、画像生成のいずれかの画面が開いている場合は有効
            return false
        default: // "settings" または nil (初期状態など) の場合は無効
            return true
        }
    }
    
    init() {
        let sm = ServerManager()
        _serverManager = State(wrappedValue: sm)
        _executor = State(wrappedValue: CommandExecutor(serverManager: sm))
#if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false  // これでタブ機能無効化 & メニュー項目非表示
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            // ContentViewにrefreshTriggerのPublisherを渡します。
            ContentView(
                serverManager: serverManager,
                executor: executor,
                selection: $selection,
                showingInspector: $showingInspector,
                showingAddModelsSheet: $showingAddModelsSheet,
                showingAddServerSheet: $showingAddServerSheet,
                shouldClearChat: $shouldClearChat,
                shouldClearGeneration: $shouldClearGeneration,
                isPulling: $isPulling
            )
#if os(macOS)
            .frame(minWidth: 1000, minHeight: 500)
#elseif os(visionOS)
            .frame(minWidth: 700, maxWidth: 1200, minHeight: 500, maxHeight: 900)
#endif
            .environment(appRefreshTrigger)
            .environment(imageSettings)
            .environment(chatSettings)
            .environment(serverManager)
            .environment(executor)
            .onAppear {
                localNetworkChecker.refresh()
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
        }
#if os(visionOS)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
#endif
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
            
            // 表示メニュー
            CommandGroup(before: .sidebar) {
                Picker("View", selection: $selection) {
                    Label("Server", systemImage: "server.rack")
                        .tag("server" as String?)
                        .keyboardShortcut("1", modifiers: .command)
                    Label("Models", systemImage: "tray.full")
                        .tag("models" as String?)
                        .keyboardShortcut("2", modifiers: .command)
                    Label("Chat", systemImage: "message")
                        .tag("chat" as String?)
                        .keyboardShortcut("3", modifiers: .command)
                    Label("Image Generation", systemImage: "photo")
                        .tag("image_generation" as String?)
                        .keyboardShortcut("4", modifiers: .command)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button(action: {
                    appRefreshTrigger.send()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isMenuActionDisabled) // ここで無効化を適用
                
                Divider()
                
                // 画像拡大縮小メニュー
                Group {
                    Button(action: {
                        NotificationCenter.default.post(name: .previewZoomIn, object: nil)
                    }) {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .previewZoomOut, object: nil)
                    }) {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .previewActualSize, object: nil)
                    }) {
                        Label("Actual Size", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
                .disabled(executor.previewImage == nil)
                
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

                Button(action: {
                    // 画像生成クリア要求を設定
                    shouldClearGeneration = true
                }) {
                    Label(String(localized: "New Generation"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("r", modifiers: [.option, .command])
                .disabled(selection != "image_generation")
            }
            
#else
            // macOS以外（iOS / iPadOS / visionOS）
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
            
            // 表示メニュー
            CommandGroup(before: .sidebar) {
                Picker("View", selection: $selection) {
                    Label("Server", systemImage: "server.rack")
                        .tag("server" as String?)
                        .keyboardShortcut("1", modifiers: .command)
                    Label("Models", systemImage: "tray.full")
                        .tag("models" as String?)
                        .keyboardShortcut("2", modifiers: .command)
                    Label("Chat", systemImage: "message")
                        .tag("chat" as String?)
                        .keyboardShortcut("3", modifiers: .command)
                    Label("Image Generation", systemImage: "photo")
                        .tag("image_generation" as String?)
                        .keyboardShortcut("4", modifiers: .command)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button(action: {
                    appRefreshTrigger.send()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isMenuActionDisabled) // ここで無効化を適用
                
                Divider()
                
                // 画像拡大縮小メニュー
                Group {
                    Button(action: {
                        NotificationCenter.default.post(name: .previewZoomIn, object: nil)
                    }) {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .previewZoomOut, object: nil)
                    }) {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .previewActualSize, object: nil)
                    }) {
                        Label("Actual Size", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
                .disabled(executor.previewImage == nil)
                
                Divider()
            }
            
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

                Button(action: {
                    // 画像生成クリア要求を設定
                    shouldClearGeneration = true
                }) {
                    Label(String(localized: "New Generation"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("r", modifiers: [.option, .command])
                .disabled(selection != "image_generation")
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
