import Foundation

/// Ollama APIの /api/tags エンドポイントから返されるモデル詳細の内部構造体
struct OllamaModelDetails: Codable, Hashable {
    let parent_model: String? // Optional because it might be empty
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

/// APIレスポンスの多様なJSON値をデコードするための汎用enum
enum JSONValue: Codable, Hashable {
    case int(Int)
    case int64(Int64)
    case string(String)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // 型のチェック順序を最適化：複雑な型（オブジェクト、配列）を先に試す
        if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let int64Value = try? container.decode(Int64.self) {
            self = .int64(int64Value)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if container.decodeNil() { // null値のチェックを追加
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .int64(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil() // null値のエンコードを追加
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
    
    // 値を文字列として取り出すヘルパー
    var stringValue: String {
        switch self {
        case .int(let value): return String(value)
        case .int64(let value): return String(value)
        case .string(let value): return value
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return "null"
        default: return "" // Array/Objectの場合は空文字
        }
    }

    // 値をIntとして取り出すヘルパー
    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .int64(let value): return Int(value)
        case .string(let value): return Int(value)
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    // 値をInt64として取り出すヘルパー
    var int64Value: Int64? {
        switch self {
        case .int(let value): return Int64(value)
        case .int64(let value): return value
        case .string(let value): return Int64(value)
        case .double(let value): return Int64(value)
        default: return nil
        }
    }
}


/// Ollama APIの /api/tags エンドポイントから返される個々のモデル情報を表すデータモデル
struct OllamaModel: Identifiable, Hashable, Codable {
    let id = UUID() // テーブルビューで各行を一意に識別するためのID (Codableの対象外)
    var originalIndex: Int = 0 // 新しく追加: 元のリスト順のインデックス (Codableの対象外)

    let name: String
    let model: String // name と同じ値だが、APIレスポンスに含まれるため保持
    let modified_at: String // ISO 8601形式の文字列
    let size: Int64 // バイト単位の数値
    let digest: String
    let details: OllamaModelDetails? // detailsオブジェクトはOptionalにする
    var capabilities: [String]?

    // Codable プロトコルのために必要な CodingKeys (originalIndexとidはデコード対象外)
    enum CodingKeys: String, CodingKey {
        case name
        case model
        case modified_at
        case size
        case digest
        case details
        case capabilities
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


    // MARK: - Sorting Helpers

    /// サイズ (バイト単位の数値) をGB単位のDoubleに変換して比較用に使用
    var comparableSize: Double {
        return Double(size) // sizeがInt64なので直接Doubleに変換
    }

    /// modified_at (ISO 8601文字列) をDateオブジェクトに変換して比較用に使用
    var comparableModifiedDate: Date {
        let formatter = ISO8601DateFormatter()
        // オプションを追加して、ミリ秒とタイムゾーンの両方に対応できるようにする
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.date(from: modified_at) ?? Date.distantPast
    }

    /// サイズを判読可能な文字列に変換するヘルパー
    var formattedSize: String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }

    /// modified_at を判読可能な日付文字列に変換するヘルパー
    var formattedModifiedAt: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium // 例: Jul 24, 2025
        dateFormatter.timeStyle = .short // 例: 9:30 PM
        return dateFormatter.string(from: comparableModifiedDate)
    }
}

/// Ollama APIの /api/tags エンドポイントからのレスポンス構造体
struct OllamaApiModelsResponse: Codable {
    let models: [OllamaModel]
}
