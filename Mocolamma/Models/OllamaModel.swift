import Foundation

/// Ollama APIの /api/tags エンドポイントから返されるモデル詳細の内部構造体
struct OllamaModelDetails: Codable, Hashable {
    let parent_model: String? // 親モデルが空の場合があるためOptional
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
    let context_length: Int?
}

/// Ollama APIの /api/tags エンドポイントから返される個々のモデル情報を表すデータモデル
struct OllamaModel: Identifiable, Hashable, Codable {
    var id: String { name } // テーブルビューで各行を一意に識別するためのID (Codableの対象外)
    var originalIndex: Int = 0
    
    let name: String
    let model: String // name と同じ値だが、APIレスポンスに含まれるため保持
    let modified_at: String // ISO 8601形式の文字列
    let size: Int64 // バイト単位の数値
    let digest: String
    var details: OllamaModelDetails? // detailsオブジェクトはOptionalにする
    var capabilities: [String]?
    var statusWeight: Int = 0 // UIでのソート用：0=なし, 1=ロード中, 2=ロード済み, 3=成功フィードバック
    
    // Codable プロトコルのために必要な CodingKeys (originalIndex, id, statusWeightはデコード対象外)
    enum CodingKeys: String, CodingKey {
        case name
        case model
        case modified_at
        case size
        case digest
        case details
        case capabilities
    }
    
    // 便宜のためのメンバーワーズイニシャライザ
    init(name: String, model: String, modifiedAt: String, size: Int64, digest: String, details: OllamaModelDetails?, capabilities: [String]?, originalIndex: Int = 0) {
        self.name = name
        self.model = model
        self.modified_at = modifiedAt
        self.size = size
        self.digest = digest
        self.details = details
        self.capabilities = capabilities
        self.originalIndex = originalIndex
    }
    
    // Decodable のカスタムイニシャライザ
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.model = try container.decode(String.self, forKey: .model)
        self.modified_at = try container.decode(String.self, forKey: .modified_at)
        self.size = try container.decode(Int64.self, forKey: .size)
        self.digest = try container.decode(String.self, forKey: .digest)
        self.details = try container.decodeIfPresent(OllamaModelDetails.self, forKey: .details)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities)
        
        // originalIndex は API レスポンスに含まれないため、ここでは初期化しない
        // CommandExecutor で API 応答後に設定する
        self.originalIndex = 0 // デフォルト値
    }
    
    // MARK: - Cached Properties
    
    // キャッシュされたプロパティを使用して、リストスクロール時の再計算を防止
    // OllamaModelはHashableプロトコル等でmutating関数と相性が悪い場合があるため、遅延評価は行わずinit/decode時に計算するか、
    // DateFormatterの生成が重いため静的Formatterを使用するアプローチに変更
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
    
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    // MARK: - Sorting Helpers
    
    /// サイズ (バイト単位の数値) をGB単位のDoubleに変換して比較用に使用
    var comparableSize: Double {
        return Double(size) // sizeがInt64なので直接Doubleに変換
    }
    
    /// modified_at (ISO 8601文字列) をDateオブジェクトに変換して比較用に使用
    var comparableModifiedDate: Date {
        return Self.iso8601Formatter.date(from: modified_at) ?? Date.distantPast
    }
    
    /// サイズを判読可能な文字列に変換するヘルパー
    var formattedSize: String {
        return Self.byteCountFormatter.string(fromByteCount: size)
    }
    
    /// modified_at を判読可能な日付文字列に変換するヘルパー
    var formattedModifiedAt: String {
        return Self.displayDateFormatter.string(from: comparableModifiedDate)
    }
    
    /// 画像生成モデルかどうかを判定するヘルパー
    var isImageModel: Bool {
        // capabilitiesに"image"が含まれているか
        if let caps = capabilities, caps.contains(where: { $0.lowercased() == "image" }) {
            return true
        }
        return false
    }
    
    /// チャット（Completion）に対応しているモデルかどうかを判定します。
    var supportsCompletion: Bool {
        // capabilitiesがあればそれを尊重
        if let caps = capabilities {
            return caps.contains(where: { $0.lowercased() == "completion" })
        }
        
        // capabilitiesがまだ取得できていない状態などは、確実な判定ができないためfalseを返す
        return false
    }

    /// ビジョンに対応しているモデルかどうかを判定します。
    var supportsVision: Bool {
        if let caps = capabilities {
            return caps.contains(where: { $0.lowercased() == "vision" })
        }
        return false
    }

    /// オーディオに対応しているモデルかどうかを判定します。
    var supportsAudio: Bool {
        if let caps = capabilities {
            return caps.contains(where: { $0.lowercased() == "audio" })
        }
        return false
    }

    /// 数値をカンマ区切りの文字列にフォーマットするヘルパー
    static func formatDecimal(_ value: Int) -> String {
        return decimalFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension OllamaModel {
    static let noModelsAvailable = OllamaModel(
        name: "No models available",
        model: "no_models_available",
        modifiedAt: ISO8601DateFormatter().string(from: Date()),
        size: 0,
        digest: "dummy",
        details: nil,
        capabilities: nil,
        originalIndex: -1
    )
}

/// Ollama APIの /api/tags エンドポイントからのレスポンス構造体
struct OllamaApiModelsResponse: Codable {
    let models: [OllamaModel]
}
