import Foundation
import Combine // Combineフレームワークをインポートして@Publishedの変更を監視可能にする

// MARK: - サーバーマネージャー

/// アプリケーション内でOllamaサーバーのリストと現在の選択状態を管理するクラスです。
/// サーバー情報はUserDefaultsに永続化されます。
class ServerManager: ObservableObject {
    // サーバー情報のUserDefaultsキー
    private let serversKey = "saved_ollama_servers"
    // 選択されたサーバーIDのUserDefaultsキー
    private let selectedServerIDKey = "selected_ollama_server_id"

    /// アプリケーションで利用可能なOllamaサーバーのリスト。
    @Published var servers: [ServerInfo] {
        didSet {
            // serversが変更されたときにUserDefaultsに保存
            saveServers()
        }
    }

    /// 現在選択されているサーバーのID。
    @Published var selectedServerID: ServerInfo.ID? {
        didSet {
            // 選択されたIDが変更されたときにUserDefaultsに保存
            saveSelectedServerID()
            // @Publishedプロパティの変更は自動的にobjectWillChangeを通知するため、
            // ここでobjectWillChange.send()を明示的に呼び出す必要はありません。
            // また、view update中にこれを呼び出すと警告の原因となります。
        }
    }

    /// 各サーバーの接続状態を保持する辞書 (nil: チェック中, true: 接続済み, false: 未接続)
    @Published var serverConnectionStatuses: [ServerInfo.ID: Bool?] = [:]

    /// 現在選択されているサーバーのホストURL。
    /// 選択されているサーバーがない場合は、デフォルトのローカルホストを返します。
    var currentServerHost: String {
        if let selectedID = selectedServerID,
           let selectedServer = servers.first(where: { $0.id == selectedID }) {
            return selectedServer.host
        }
        // 選択されたサーバーがない場合のフォールバック（最初のサーバーがあればそれ、なければデフォルト）
        return servers.first?.host ?? "localhost:11434"
    }

    /// ServerManagerのイニシャライザ。保存されたサーバーリストを読み込み、デフォルトサーバーを設定します。
    init() {
        // UserDefaultsからサーバーリストを読み込む
        if let savedServersData = UserDefaults.standard.data(forKey: serversKey),
           let decodedServers = try? JSONDecoder().decode([ServerInfo].self, from: savedServersData) {
            self.servers = decodedServers
        } else {
            // 保存されたサーバーがない場合は空の配列で初期化
            self.servers = []
        }

        // デフォルトの「ローカル」サーバーが存在するか確認し、なければ追加
        let localServer = ServerInfo(name: "Local", host: "localhost:11434")
        if !servers.contains(where: { $0.id == localServer.id || ($0.name == localServer.name && $0.host == localServer.host) }) {
            servers.insert(localServer, at: 0)
        }
        
        // 以前選択されていたサーバーIDを読み込む
        if let savedSelectedIDString = UserDefaults.standard.string(forKey: selectedServerIDKey),
           let savedSelectedID = UUID(uuidString: savedSelectedIDString) {
            self.selectedServerID = savedSelectedID
        } else {
            // 以前の選択がない場合は「ローカル」サーバーをデフォルトで選択
            self.selectedServerID = servers.first(where: { $0.name == "Local" && $0.host == "localhost:11434" })?.id
        }

        // selectedServerIDがnilの場合、最初のサーバーを選択（ローカルサーバーがあればそれが選択される）
        if self.selectedServerID == nil && !self.servers.isEmpty {
            self.selectedServerID = self.servers.first?.id
        }
    }

    /// 新しいサーバーをリストに追加します。
    /// - Parameters:
    ///   - name: 追加するサーバーの名前。
    ///   - host: 追加するサーバーのホストURL。
    func addServer(name: String, host: String) {
        let newServer = ServerInfo(name: name, host: host)
        servers.append(newServer)
        // 新しく追加されたサーバーを選択状態にする
        selectedServerID = newServer.id
    }
    
    /// 既存のサーバーを更新します。IDに基づいてサーバーを見つけ、名前とホストを更新します。
    /// - Parameter serverInfo: 更新するサーバー情報を含むServerInfoオブジェクト。IDは既存のものと一致する必要があります。
    func updateServer(serverInfo: ServerInfo) {
        if let index = servers.firstIndex(where: { $0.id == serverInfo.id }) {
            servers[index] = serverInfo
        }
    }

    /// 指定されたサーバーをリストから削除します。
    /// - Parameter server: 削除するServerInfoオブジェクト。
    func deleteServer(_ server: ServerInfo) {
        servers.removeAll(where: { $0.id == server.id })
        // 削除されたサーバーが選択されていた場合、選択状態をクリアまたは別のサーバーを選択
        if selectedServerID == server.id {
            // 最初のサーバーがあればそれ、なければnilにする
            selectedServerID = servers.first?.id
        }
        serverConnectionStatuses[server.id] = nil
    }

    /// 指定されたサーバーの接続状態を更新します。
    func updateServerConnectionStatus(serverID: ServerInfo.ID, status: Bool?) {
        serverConnectionStatuses[serverID] = status
    }

    /// 現在のサーバーリストをUserDefaultsに保存します。
    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: serversKey)
        }
    }

    /// 現在選択されているサーバーIDをUserDefaultsに保存します。
    private func saveSelectedServerID() {
        UserDefaults.standard.set(selectedServerID?.uuidString, forKey: selectedServerIDKey)
    }
}
