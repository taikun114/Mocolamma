import Foundation

// MARK: - サーバー情報モデル

/// Ollamaサーバーの接続情報を表すデータモデルです。
/// Identifiable, Codable, Equatable に準拠し、リスト表示や永続化を可能にします。
struct ServerInfo: Identifiable, Codable, Equatable {
    // デフォルトサーバー用の固定ID
    static let defaultServerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")! // "default_server"のUUID
    
    var connectionStatus: Bool? = nil // 接続状態 (true: 接続済み, false: 接続失敗, nil: 未確認)
    let id: UUID // 各サーバーを一意に識別するためのID
    var name: String // サーバーの表示名
    var host: String // サーバーのホストURL (例: "localhost:11434" または "192.168.1.50:11434")
    var iconName: String // サーバーのアイコン名 (SF Symbol)
    let isDemo: Bool // デモサーバーであるかどうか
    
    /// 新しいServerInfoインスタンスを初期化します。
    /// - Parameters:
    ///   - id: サーバーの一意なID。デフォルトで新しいUUIDが生成されます。
    ///   - name: サーバーの表示名。
    ///   - host: サーバーのホストURL。
    ///   - iconName: サーバーのアイコン名。
    ///   - isDemo: デモサーバーかどうか。
    init(id: UUID = UUID(), name: String, host: String, iconName: String = "server.rack", isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.iconName = iconName
        self.isDemo = isDemo
    }
    
    // Codableのためのキー
    enum CodingKeys: String, CodingKey {
        case connectionStatus
        case id
        case name
        case host
        case iconName
        case isDemo
    }
    
    // Decodableのためのイニシャライザー
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionStatus = try container.decodeIfPresent(Bool.self, forKey: .connectionStatus)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "server.rack"
        // isDemoプロパティが存在しない場合でもnilを許容し、デフォルト値をfalseとする
        isDemo = try container.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }
    
    // Equatableプロトコルの実装（ID・名前・ホスト・アイコンで比較）
    static func == (lhs: ServerInfo, rhs: ServerInfo) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.host == rhs.host && lhs.iconName == rhs.iconName && lhs.isDemo == rhs.isDemo
    }
}
