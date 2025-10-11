import Foundation

/// Ollama APIの /api/tags エンドポイントから返されるモデル詳細の内部構造体
struct OllamaModelDetails: Codable, Hashable {
    let parent_model: String? // Optional because it might be empty
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
    let context_length: Int?
}




/// Ollama APIの /api/tags エンドポイントから返される個々のモデル情報を表すデータモデル
struct OllamaModel: Identifiable, Hashable, Codable {
    var id: String { digest } // テーブルビューで各行を一意に識別するためのID (Codableの対象外)
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

    // Memberwise initializer for convenience
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