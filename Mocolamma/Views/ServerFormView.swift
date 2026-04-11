import SwiftUI
import UniversalSFSymbolsPicker

// MARK: - サーバーフォームビュー

/// 新しいOllamaサーバーの追加、または既存サーバーの編集を行うためのシートビューです。
/// サーバー名とホストURLの入力欄を提供し、保存時に接続確認を行います。
struct ServerFormView: View {
    @Environment(\.dismiss) var dismiss // シートを閉じるための環境変数
    @Environment(RefreshTrigger.self) var appRefreshTrigger
    var serverManager: ServerManager // ServerManagerのインスタンスを受け取ります
    var executor: CommandExecutor // @ObservedObjectを削除
    
    @State private var serverNameInput: String
    @State private var serverHostInput: String
    @State private var serverIconInput: String // サーバーのアイコン
    @State private var isShowingSymbolPicker = false // シンボルピッカーの表示状態
    @State private var showingConnectionErrorAlert = false // 接続エラーアラートの表示/非表示
    @State private var showingValidationErrorAlert = false // 入力バリデーションエラーのアラート
    @State private var validationErrorMessage = "" // バリデーションエラーメッセージ
    @State private var isVerifying = false // 接続確認中の状態を追跡
    @State private var connectionStatus: ServerConnectionStatus? // 最新の接続ステータス
    @FocusState private var isNameFieldFocused: Bool
    var editingServer: ServerInfo?
    
    /// 初期化。追加の場合はnil、編集の場合は既存のServerInfoを渡します。
    /// - Parameters:
    ///   - serverManager: ServerManagerのインスタンス。
    ///   - executor: CommandExecutorのインスタンス（接続確認用）。
    ///   - editingServer: 編集中のServerInfoオブジェクト。新しいサーバー追加の場合はnil。
    init(serverManager: ServerManager, executor: CommandExecutor, editingServer: ServerInfo?) {
        self.serverManager = serverManager
        self.executor = executor
        self.editingServer = editingServer
        
        // 編集モードの場合、既存のサーバー情報で入力フィールドを初期化
        _serverNameInput = State(initialValue: editingServer?.name ?? "")
        _serverHostInput = State(initialValue: editingServer?.host ?? "")
        _serverIconInput = State(initialValue: editingServer?.iconName ?? "server.rack")
    }
    
    // 保存/更新ボタンを無効化するための計算プロパティ
    private var isSaveButtonDisabled: Bool {
        serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
#if os(macOS)
            Text(editingServer == nil ? "Add Server" : "Edit Server")
                .font(.title)
                .bold()
#endif
            
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    // アイコン選択ボタン
                    Button {
                        isShowingSymbolPicker = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 54, height: 54)
                            
                            Image(systemName: serverIconInput)
                                .font(.system(size: 24))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Select Icon"))
                    .symbolPicker(isPresented: $isShowingSymbolPicker, selection: $serverIconInput)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g., Ollama Server", text: $serverNameInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                save()
                            }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Host")
                        .font(.headline)
                    TextField("e.g., localhost:11434 or 192.168.1.50:11434", text: $serverHostInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            save()
                        }
                }
                
#if !os(macOS)
                if isVerifying {
                    HStack {
                        ProgressView()
                        Text("Connecting...")
                        Spacer()
                    }
                    .padding(.top)
                }
#endif
                
                Spacer()
            }
            
#if os(macOS)
            HStack(alignment: .center) {
                if isVerifying {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Connecting...")
                }
                Spacer()
                Button("Cancel") { // キャンセルボタン
                    dismiss() // シートを閉じる
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button(editingServer == nil ? "Save" : "Update") { // 保存/更新ボタン
                    save()
                }
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .controlSize(.large)
                .disabled(isSaveButtonDisabled)
            }
#endif
        }
        .padding()
#if os(macOS)
        .frame(width: 400, height: 270) // フォームのサイズを少し広げる
#endif
        .alert(LocalizedStringKey("ConnectionError.title"), isPresented: $showingConnectionErrorAlert) {
            Button("OK") { }
                .keyboardShortcut(.defaultAction)
            Button(editingServer == nil ? "Add Anyway" : "Update Anyway") {
                let processedHost = processHostInput(serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines))
                if let server = editingServer {
                    // 編集モード: サーバーを更新
                    serverManager.updateServer(
                        serverInfo: ServerInfo(id: server.id, name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost, iconName: serverIconInput)
                    )
                } else {
                    // 追加モード: 新しいサーバーを追加
                    serverManager.addServer(name: serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines), host: processedHost, iconName: serverIconInput)
                }
                appRefreshTrigger.send() // リフレッシュをトリガー
                dismiss() // シートを閉じる
            }
        } message: {
            Text(connectionStatus?.localizedDescription ?? String(localized: "Could not connect to the server."))
        }
        .alert(String(localized: "Validation Error"), isPresented: $showingValidationErrorAlert) {
            Button("OK") { }
        } message: {
            Text(validationErrorMessage)
        }
#if !os(macOS)
        .navigationTitle(editingServer == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if #available(iOS 26.0, visionOS 26.0, *) {
                    Button(role: .confirm) {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaveButtonDisabled)
                    .applyGlassProminentButtonStyle(isDisabled: isSaveButtonDisabled)
                } else {
                    Button(action: {
                        save()
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaveButtonDisabled)
                    .applyGlassProminentButtonStyle(isDisabled: isSaveButtonDisabled)
                }
            }
        }
        .onAppear {
            isNameFieldFocused = true
        }
        .interactiveDismissDisabled()
#endif
    }
    
    /// 保存/更新処理
    private func save() {
        guard !isSaveButtonDisabled else { return }
        
        let trimmedName = serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = serverHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let processedHost = processHostInput(trimmedHost)
        
        // 1. 重複チェック（ポート番号補完後のホスト名で比較）
        let isDuplicateHost = serverManager.servers.contains { server in
            // 自分自身（編集中のサーバー）は除外
            if let editingID = editingServer?.id, server.id == editingID {
                return false
            }
            return server.host.lowercased() == processedHost.lowercased()
        }
        
        if isDuplicateHost {
            validationErrorMessage = String(localized: "A server with the same host already exists.")
            showingValidationErrorAlert = true
            return
        }
        
        // 2. ホスト形式の簡易チェック（スペースの有無など）
        if trimmedHost.contains(" ") {
            validationErrorMessage = String(localized: "Host cannot contain spaces.")
            showingValidationErrorAlert = true
            return
        }
        
        Task {
            // ホスト名が「demo-mode」の場合はデモサーバーとして扱う
            if trimmedHost.lowercased() == "demo-mode" {
                isVerifying = false
                if let server = editingServer {
                    serverManager.updateServer(
                        serverInfo: ServerInfo(id: server.id, name: trimmedName, host: "demo-mode", iconName: serverIconInput, isDemo: true)
                    )
                } else {
                    serverManager.addServer(name: trimmedName, host: "demo-mode", iconName: serverIconInput, isDemo: true)
                }
                appRefreshTrigger.send()
                dismiss()
            } else {
                isVerifying = true
                
                let status = await executor.checkAPIConnectivity(host: processedHost)
                connectionStatus = status
                isVerifying = false
                
                if case .connected = status {
                    if let server = editingServer {
                        serverManager.updateServer(
                            serverInfo: ServerInfo(id: server.id, name: trimmedName, host: processedHost, iconName: serverIconInput)
                        )
                    } else {
                        serverManager.addServer(name: trimmedName, host: processedHost, iconName: serverIconInput)
                    }
                    appRefreshTrigger.send()
                    dismiss()
                } else {
                    // 接続失敗: アラートを表示
                    showingConnectionErrorAlert = true
                }
            }
        }
    }
    
    private func processHostInput(_ host: String) -> String {
        let lowercasedHost = host.lowercased()
        
        // ホスト名が「demo-mode」の場合は特別処理
        if lowercasedHost == "demo-mode" {
            return "demo-mode"
        }
        
        // 最後のコロンを探す
        if let lastColonIndex = lowercasedHost.lastIndex(of: ":") {
            let afterColon = lowercasedHost[lowercasedHost.index(after: lastColonIndex)...]
            // 最後のコロンの後の文字がすべて数字かどうかを確認
            if !afterColon.isEmpty && afterColon.allSatisfy({ $0.isNumber }) {
                // ポート番号が存在する場合はそのまま返す
                return lowercasedHost
            }
        }
        
        // コロンがない、またはコロンの後にポート番号がない場合は、デフォルトポートを追加する
        return lowercasedHost + ":11434"
    }
}

// MARK: - Symbol Picker Helper

/// SFSymbolPickerの検索状態などを管理するためのラッパービューです。
struct SymbolPickerWrapper: View {
    @Binding var isPresented: Bool
    @Binding var selection: String
    let showAs: SFSymbolPickerDisplayMode
    
    @State private var searchText = ""
    
    var body: some View {
        SFSymbolPicker(
            isPresented: $isPresented,
            selection: Binding(
                get: { selection },
                set: { if let val = $0 { selection = val } }
            ),
            showAs: showAs,
            showSearchBar: showAs == .popover, // ポップオーバー時はカスタム検索バーを表示、シート時は非表示
            showIconName: true,
            searchText: $searchText
        )
        .conditionalSearchable(show: showAs == .sheet, text: $searchText)
    }
}

private extension View {
    @ViewBuilder
    func conditionalSearchable(show: Bool, text: Binding<String>) -> some View {
        if show {
            self.searchable(text: text)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func symbolPicker(isPresented: Binding<Bool>, selection: Binding<String>) -> some View {
#if os(iOS)
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                SymbolPickerWrapper(
                    isPresented: isPresented,
                    selection: selection,
                    showAs: .sheet
                )
            }
        }
#else
        self.popover(isPresented: isPresented, arrowEdge: .top) {
            SymbolPickerWrapper(
                isPresented: isPresented,
                selection: selection,
                showAs: .popover
            )
            .frame(width: 500, height: 400)
        }
#endif
    }
}

// MARK: - プレビュー

#Preview {
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
    // 追加モードのプレビュー
    return ServerFormView(serverManager: previewServerManager, executor: previewCommandExecutor, editingServer: nil)
}

#Preview("Edit Mode") {
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    let dummyServer = ServerInfo(name: "Test Server", host: "192.168.1.100:11434")
    
    // 編集モードのプレビュー
    return ServerFormView(serverManager: previewServerManager, executor: previewCommandExecutor, editingServer: dummyServer)
}
