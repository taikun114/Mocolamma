import SwiftUI
import Foundation

// MARK: - チャットAPI リクエスト/レスポンス モデル

/// チャット会話における単一のメッセージを表します。
class ChatMessage: ObservableObject, Identifiable, Codable, Equatable {
    let id = UUID()
    @Published var role: String
    @Published var content: String
    @Published var thinking: String?
    @Published var images: [String]? // Base64でエンコードされた画像
    @Published var toolCalls: [ToolCall]?
    @Published var toolName: String?
    @Published var createdAt: String? // メッセージが作成された日時
    @Published var totalDuration: Int? // 応答生成にかかった合計時間 (ナノ秒)
    @Published var evalCount: Int? // 応答内のトークン数
    @Published var evalDuration: Int? // 応答生成にかかった時間 (ナノ秒)
    @Published var isStreaming: Bool = false // ストリーミング中かどうかを示すフラグ
    @Published var isStopped: Bool = false // ストリーミングがユーザーによって停止されたかどうかを示すフラグ
    @Published var isThinkingCompleted: Bool = false // シンキングが完了したかどうかを示すフラグ
    @Published var isProcessingImages: Bool = false // 画像の変換処理中かどうかを示すフラグ
    
    // 画像生成関連のプロパティ
    @Published var generatedImage: String? // 生成された画像 (Base64)
    @Published var imageProgressCompleted: Int? // 現在のステップ数
    @Published var imageProgressTotal: Int? // 合計ステップ数
    @Published var isImageGeneration: Bool = false // 画像生成メッセージかどうか
    
    // 新しいプロパティ（やり直し履歴など）
    @Published var revisions: [ChatMessage] = [] // やり直し履歴
    @Published var currentRevisionIndex: Int = 0 // 現在の履歴インデックス
    @Published var originalContent: String? // メッセージの最初の内容を保持
    @Published var latestContent: String? // メッセージの最新のやり直し結果を保持
    @Published var latestGeneratedImage: String? // 最新の生成画像を保持
    @Published var finalThinking: String? // 最終的な思考内容を保持
    @Published var finalIsThinkingCompleted: Bool = false // 最終的な思考完了状態を保持
    @Published var finalCreatedAt: String? // 最終的な作成日時
    @Published var finalTotalDuration: Int? // 最終的な合計時間
    @Published var finalEvalCount: Int? // 最終的なトークン数
    @Published var finalEvalDuration: Int? // 最終的な評価時間
    @Published var finalIsStopped: Bool = false // 最終的な停止状態
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case thinking
        case images
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
        case generatedImage = "generated_image"
        case isImageGeneration = "is_image_generation"
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(String.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        self.images = try container.decodeIfPresent([String].self, forKey: .images)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.totalDuration = try container.decodeIfPresent(Int.self, forKey: .totalDuration)
        self.evalCount = try container.decodeIfPresent(Int.self, forKey: .evalCount)
        self.evalDuration = try container.decodeIfPresent(Int.self, forKey: .evalDuration)
        self.generatedImage = try container.decodeIfPresent(String.self, forKey: .generatedImage)
        self.isImageGeneration = try container.decodeIfPresent(Bool.self, forKey: .isImageGeneration) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(totalDuration, forKey: .totalDuration)
        try container.encodeIfPresent(evalCount, forKey: .evalCount)
        try container.encodeIfPresent(evalDuration, forKey: .evalDuration)
        try container.encodeIfPresent(generatedImage, forKey: .generatedImage)
        try container.encode(isImageGeneration, forKey: .isImageGeneration)
    }
    
    // 新しいメッセージを作成するためのデフォルトイニシャライザ
    init(role: String, content: String, thinking: String? = nil, images: [String]? = nil, toolCalls: [ToolCall]? = nil, toolName: String? = nil, createdAt: String? = nil, totalDuration: Int? = nil, evalCount: Int? = nil, evalDuration: Int? = nil, isStreaming: Bool = false, isStopped: Bool = false, isThinkingCompleted: Bool = false, generatedImage: String? = nil, isImageGeneration: Bool = false) {
        self.role = role
        self.content = content
        self.thinking = thinking
        self.images = images
        self.toolCalls = toolCalls
        self.toolName = toolName
        self.createdAt = createdAt
        self.totalDuration = totalDuration
        self.evalCount = evalCount
        self.evalDuration = evalDuration
        self.isStreaming = isStreaming
        self.isStopped = isStopped
        self.isThinkingCompleted = isThinkingCompleted
        self.generatedImage = generatedImage
        self.isImageGeneration = isImageGeneration
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// メッセージ内のツール呼び出しを表します。
struct ToolCall: Codable, Hashable {
    let function: ToolFunction
}

/// ツール呼び出しの関数の詳細を表します。
struct ToolFunction: Codable, Hashable {
    let name: String
    let arguments: [String: JSONValue] // 柔軟な引数のためにJSONValueを使用
}

/// /api/chat エンドポイントのリクエストボディを表します。
struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let think: Bool?
    let keepAlive: JSONValue?
    let options: ChatRequestOptions?
    let tools: [ToolDefinition]?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case think
        case keepAlive = "keep_alive"
        case options
        case tools
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(think, forKey: .think)
        try container.encodeIfPresent(keepAlive, forKey: .keepAlive)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

/// チャットリクエストの思考オプションを表します。
enum ThinkingOption: String, CaseIterable, Identifiable {
    case none = "ThinkingOption_None"
    case on = "ThinkingOption_On"
    case off = "ThinkingOption_Off"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

/// 繰り返し参照範囲のオプションを表します。
enum RepeatLastNOption: String, CaseIterable, Identifiable {
    case none = "RepeatLastN_None"
    case disabled = "RepeatLastN_Disabled"
    case custom = "RepeatLastN_Custom"
    case max = "RepeatLastN_Max"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

/// 最大出力数のオプションを表します。
enum NumPredictOption: String, CaseIterable, Identifiable {
    case none = "NumPredict_None"
    case custom = "NumPredict_Custom"
    case unlimited = "NumPredict_Unlimited"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

/// モデルの保持（Keep Alive）オプションを表します。
enum KeepAliveOption: String, CaseIterable, Identifiable {
    case `default` = "KeepAlive_Default"
    case immediate = "KeepAlive_Immediate"
    case m1 = "KeepAlive_1m"
    case m3 = "KeepAlive_3m"
    case m5 = "KeepAlive_5m"
    case m10 = "KeepAlive_10m"
    case m15 = "KeepAlive_15m"
    case m30 = "KeepAlive_30m"
    case h1 = "KeepAlive_1h"
    case indefinite = "KeepAlive_Indefinite"
    case custom = "KeepAlive_Custom"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
    
    /// APIに送信するための値を返します。
    func apiValue(customValue: Int, customUnit: KeepAliveUnit) -> JSONValue? {
        switch self {
        case .default: return nil
        case .immediate: return .int(0)
        case .m1: return .string("1m")
        case .m3: return .string("3m")
        case .m5: return .string("5m")
        case .m10: return .string("10m")
        case .m15: return .string("15m")
        case .m30: return .string("30m")
        case .h1: return .string("1h")
        case .indefinite: return .int(-1)
        case .custom:
            return .string("\(customValue)\(customUnit.rawValue)")
        }
    }
}

/// Keep Aliveのカスタム単位を表します。
enum KeepAliveUnit: String, CaseIterable, Identifiable {
    case seconds = "s"
    case minutes = "m"
    case hours = "h"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        switch self {
        case .seconds: return "Seconds"
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        }
    }
}

/// /api/chat エンドポイントのツール定義を表します。
struct ToolDefinition: Codable {
    let type: String
    let function: ToolFunctionDefinition
}

/// ツールの関数定義を表します。
struct ToolFunctionDefinition: Codable {
    let name: String
    let description: String?
    let parameters: JSONSchema?
}

/// ツールパラメータのJSONスキーマを表します。
struct JSONSchema: Codable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
}

/// JSONスキーマ内のプロパティを表します。
struct JSONSchemaProperty: Codable {
    let type: String
    let description: String?
    let `enum`: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case `enum`
    }
}

/// チャットリクエストのオプションを表します。
struct ChatRequestOptions: Codable {
    var numKeep: Int?
    var seed: Int?
    var numPredict: Int?
    var topK: Int?
    var topP: Double?
    var minP: Double?
    var typicalP: Double?
    var repeatLastN: Int?
    var temperature: Double?
    var numCtx: Int?
    var repeatPenalty: Double?
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var penalizeNewline: Bool?
    var stop: [String]?
    var numa: Bool?
    var numBatch: Int?
    var numGpu: Int?
    var mainGpu: Int?
    var useMmap: Bool?
    var numThread: Int?
    
    enum CodingKeys: String, CodingKey {
        case numKeep = "num_keep"
        case seed
        case numPredict = "num_predict"
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
        case typicalP = "typical_p"
        case repeatLastN = "repeat_last_n"
        case temperature
        case repeatPenalty = "repeat_penalty"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case penalizeNewline = "penalize_newline"
        case stop
        case numa
        case numCtx = "num_ctx"
        case numBatch = "num_batch"
        case numGpu = "num_gpu"
        case mainGpu = "main_gpu"
        case useMmap = "use_mmap"
        case numThread = "num_thread"
    }
    
    init(
        numKeep: Int? = nil,
        seed: Int? = nil,
        numPredict: Int? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        minP: Double? = nil,
        typicalP: Double? = nil,
        repeatLastN: Int? = nil,
        temperature: Double? = nil,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        penalizeNewline: Bool? = nil,
        stop: [String]? = nil,
        numa: Bool? = nil,
        numCtx: Int? = nil,
        numBatch: Int? = nil,
        numGpu: Int? = nil,
        mainGpu: Int? = nil,
        useMmap: Bool? = nil,
        numThread: Int? = nil
    ) {
        self.numKeep = numKeep
        self.seed = seed
        self.numPredict = numPredict
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.typicalP = typicalP
        self.repeatLastN = repeatLastN
        self.temperature = temperature
        self.repeatPenalty = repeatPenalty
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.penalizeNewline = penalizeNewline
        self.stop = stop
        self.numa = numa
        self.numCtx = numCtx
        self.numBatch = numBatch
        self.numGpu = numGpu
        self.mainGpu = mainGpu
        self.useMmap = useMmap
        self.numThread = numThread
    }
}

/// /api/chat エンドポイントからのストリーミング応答チャンクを表します。
struct ChatResponseChunk: Codable {
    let model: String
    let createdAt: String
    let message: ChatMessage?
    let done: Bool
    let totalDuration: Int?
    let loadDuration: Int?
    let promptEvalCount: Int?
    let promptEvalDuration: Int?
    let evalCount: Int?
    let evalDuration: Int?
    let doneReason: String?
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message
        case done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
        case doneReason = "done_reason"
    }
}

/// ツール呼び出しにおけるさまざまな引数タイプを処理するための柔軟なJSON値の型。
enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSONValue type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .bool(let bool):
            try container.encode(bool)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
    
    // 便宜のためのヘルパイニシャライザ
    init(_ value: String) { self = .string(value) }
    init(_ value: Int) { self = .int(value) }
    init(_ value: Double) { self = .double(value) }
    init(_ value: Bool) { self = .bool(value) }
    init(_ value: [JSONValue]) { self = .array(value) }
    init(_ value: [String: JSONValue]) { self = .object(value) }
    
    // 型安全なアクセスのためのヘルパープロパティ
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    
    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)): return l == r
        case (.int(let l), .int(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.array(let l), .array(let r)): return l == r
        case (.object(let l), .object(let r)): return l == r
        case (.null, .null): return true
        default: return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value): hasher.combine(value)
        case .int(let value): hasher.combine(value)
        case .double(let value): hasher.combine(value)
        case .bool(let value): hasher.combine(value)
        case .array(let value): hasher.combine(value)
        case .object(let value): hasher.combine(value)
        case .null: hasher.combine(0)
        }
    }
}

// MARK: - シード値ユーティリティ

/// Ollama APIで安全に使用できるシード値の最大値（2^53 - 1）。
let OLLAMA_SEED_SAFE_LIMIT: Int = 9007199254740991

/// シード値を安全な範囲内にクランプします。
func clampOllamaSeed(_ seed: Int) -> Int {
    max(-OLLAMA_SEED_SAFE_LIMIT, min(OLLAMA_SEED_SAFE_LIMIT, seed))
}

@MainActor
class ChatSettings: ObservableObject {
    @Published var selectedModelID: OllamaModel.ID?
    @Published var selectedModelContextLength: Int?
    @Published var selectedModelCapabilities: [String]?
    @Published var isStreamingEnabled: Bool = true
    @Published var keepAliveOption: KeepAliveOption = .default
    @Published var customKeepAliveValue: Int = 5
    @Published var customKeepAliveUnit: KeepAliveUnit = .minutes
    @Published var useCustomChatSettings: Bool = false
    @Published var chatTemperature: Double = 0.8
    @Published var isTemperatureEnabled: Bool = false
    @Published var isContextWindowEnabled: Bool = false
    @Published var contextWindowValue: Double = 2048.0
    @Published var isSystemPromptEnabled: Bool = false
    @Published var systemPrompt: String = ""
    @Published var thinkingOption: ThinkingOption = .none
    
    // 追加のカスタム設定
    @Published var repeatLastNOption: RepeatLastNOption = .none
    @Published var repeatLastNValue: Int = 64
    @Published var isRepeatPenaltyEnabled: Bool = false
    @Published var repeatPenaltyValue: Double = 1.1
    @Published var numPredictOption: NumPredictOption = .none
    @Published var numPredictValue: Int = 42
    @Published var isTopKEnabled: Bool = false
    @Published var topKValue: Int = 40
    @Published var isTopPEnabled: Bool = false
    @Published var topPValue: Double = 0.9
    @Published var isMinPEnabled: Bool = false
    @Published var minPValue: Double = 0.0
    
    // シード値設定
    @Published var isSeedEnabled: Bool = false
    @Published var seed: Int = 0 {
        didSet {
            let clamped = clampOllamaSeed(seed)
            if seed != clamped {
                seed = clamped
            }
        }
    }
    
    var finalKeepAlive: JSONValue? {
        keepAliveOption.apiValue(customValue: customKeepAliveValue, customUnit: customKeepAliveUnit)
    }
}

// MARK: - 画像生成API リクエスト/レスポンス モデル

/// /api/generate エンドポイントのリクエストボディを表します（画像生成用）。
struct ImageGenerationRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let keepAlive: JSONValue?
    let width: Int?
    let height: Int?
    let steps: Int?
    let options: ChatRequestOptions? // チャットと共通のオプションも使用可能
    
    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case keepAlive = "keep_alive"
        case width
        case height
        case steps
        case options
    }
}

/// /api/generate エンドポイントからのストリーミング応答チャンクを表します（画像生成用）。
struct ImageGenerationResponseChunk: Codable {
    let model: String
    let createdAt: String?
    let response: String?
    let done: Bool
    let image: String? // Base64でエンコードされた画像
    let completed: Int? // 現在のステップ数
    let total: Int? // 合計ステップ数
    let totalDuration: Int?
    let loadDuration: Int?
    let promptEvalCount: Int?
    let promptEvalDuration: Int?
    let evalCount: Int?
    let evalDuration: Int?
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response
        case done
        case image
        case completed
        case total
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

// MARK: - 画像生成設定

@MainActor
class ImageGenerationSettings: ObservableObject {
    @Published var selectedModelID: OllamaModel.ID?
    @Published var isStreamingEnabled: Bool = true
    @Published var keepAliveOption: KeepAliveOption = .default
    @Published var customKeepAliveValue: Int = 5
    @Published var customKeepAliveUnit: KeepAliveUnit = .minutes
    
    // 基本設定
    @Published var width: Double = 512 {
        didSet { customWidth = Int(width) }
    }
    @Published var height: Double = 512 {
        didSet { customHeight = Int(height) }
    }
    @Published var steps: Double = 8 {
        didSet { customSteps = Int(steps) }
    }
    
    // カスタム設定
    @Published var customWidthEnabled: Bool = false
    @Published var customWidth: Int = 512
    @Published var customHeightEnabled: Bool = false
    @Published var customHeight: Int = 512
    @Published var customStepsEnabled: Bool = false
    @Published var customSteps: Int = 8
    
    // シード値設定
    @Published var isSeedEnabled: Bool = false
    @Published var seed: Int = 0 {
        didSet {
            let clamped = clampOllamaSeed(seed)
            if seed != clamped {
                seed = clamped
            }
        }
    }
    
    // 実際にAPIに送る値を取得するヘルパー
    var finalWidth: Int {
        if customWidthEnabled {
            return customWidth
        }
        return Int(width)
    }
    
    var finalHeight: Int {
        if customHeightEnabled {
            return customHeight
        }
        return Int(height)
    }
    
    var finalSteps: Int {
        if customStepsEnabled {
            return customSteps
        }
        return Int(steps)
    }
    
    var finalKeepAlive: JSONValue? {
        keepAliveOption.apiValue(customValue: customKeepAliveValue, customUnit: customKeepAliveUnit)
    }
}
