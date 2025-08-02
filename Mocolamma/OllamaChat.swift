// OllamaChat.swift

import SwiftUI
import Foundation

// MARK: - Chat API Request/Response Models

/// Represents a single message in a chat conversation.
class ChatMessage: ObservableObject, Identifiable, Codable {
    let id = UUID()
    @Published var role: String
    @Published var content: String
    @Published var thinking: String?
    @Published var images: [String]? // Base64 encoded images
    @Published var toolCalls: [ToolCall]?
    @Published var toolName: String?
    @Published var createdAt: String? // メッセージが作成された日時
    @Published var totalDuration: Int? // 応答生成にかかった合計時間 (ナノ秒)
    @Published var evalCount: Int? // 応答内のトークン数
    @Published var evalDuration: Int? // 応答生成にかかった時間 (ナノ秒)
    @Published var isStreaming: Bool = false // ストリーミング中かどうかを示すフラグ
    @Published var isStopped: Bool = false // ストリーミングがユーザーによって停止されたかどうかを示すフラグ
    @Published var isThinkingCompleted: Bool = false // シンキングが完了したかどうかを示すフラグ

    // 新しいプロパティ
    @Published var revisions: [ChatMessage] = [] // やり直し履歴
    @Published var currentRevisionIndex: Int = 0 // 現在の履歴インデックス
    @Published var originalContent: String? // メッセージの最初の内容を保持
    @Published var latestContent: String? // メッセージの最新のやり直し結果を保持
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
    }

    // Default initializer for creating new messages
    init(role: String, content: String, thinking: String? = nil, images: [String]? = nil, toolCalls: [ToolCall]? = nil, toolName: String? = nil, createdAt: String? = nil, totalDuration: Int? = nil, evalCount: Int? = nil, evalDuration: Int? = nil, isStreaming: Bool = false, isStopped: Bool = false, isThinkingCompleted: Bool = false) {
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
    }
}

/// Represents a tool call within a message.
struct ToolCall: Codable, Hashable {
    let function: ToolFunction
}

/// Represents the function details of a tool call.
struct ToolFunction: Codable, Hashable {
    let name: String
    let arguments: [String: JSONValue] // Use JSONValue for flexible arguments
}

/// Represents the request body for the /api/chat endpoint.
struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let think: Bool?
    let options: ChatRequestOptions?
    let tools: [ToolDefinition]?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case think
        case options
        case tools
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(think, forKey: .think)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

/// Represents the thinking option for a chat request.
enum ThinkingOption: String, CaseIterable, Identifiable {
    case none = "ThinkingOption_None"
    case on = "ThinkingOption_On"
    case off = "ThinkingOption_Off"

    var id: String { self.rawValue }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

/// Represents tool definitions for the /api/chat endpoint.
struct ToolDefinition: Codable {
    let type: String
    let function: ToolFunctionDefinition
}

/// Represents function definition for a tool.
struct ToolFunctionDefinition: Codable {
    let name: String
    let description: String?
    let parameters: JSONSchema?
}

/// Represents a JSON schema for tool parameters.
struct JSONSchema: Codable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
}

/// Represents a property within a JSON schema.
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

/// Represents the options for a chat request.
struct ChatRequestOptions: Codable {
    let numKeep: Int?
    let seed: Int?
    let numPredict: Int?
    let topK: Int?
    let topP: Double?
    let minP: Double?
    let typicalP: Double?
    let repeatLastN: Int?
    var temperature: Double?
    var numCtx: Int? // ここを var に変更
    let repeatPenalty: Double?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let penalizeNewline: Bool?
    let stop: [String]?
    let numa: Bool?
    let numBatch: Int?
    let numGpu: Int?
    let mainGpu: Int?
    let useMmap: Bool?
    let numThread: Int?
    let keepAlive: String? // Duration string, e.g., "5m"

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
        case keepAlive = "keep_alive"
    }

    // Custom initializer to allow partial initialization
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
        numCtx: Int? = nil, // ここを追加
        numBatch: Int? = nil,
        numGpu: Int? = nil,
        mainGpu: Int? = nil,
        useMmap: Bool? = nil,
        numThread: Int? = nil,
        keepAlive: String? = nil
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
        self.numCtx = numCtx // ここを追加
        self.numBatch = numBatch
        self.numGpu = numGpu
        self.mainGpu = mainGpu
        self.useMmap = useMmap
        self.numThread = numThread
        self.keepAlive = keepAlive
    }
}


/// Represents a streaming response chunk from the /api/chat endpoint.
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

/// A flexible JSON value type to handle various argument types in tool calls.
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

    // Helper initializers for convenience
    init(_ value: String) { self = .string(value) }
    init(_ value: Int) { self = .int(value) }
    init(_ value: Double) { self = .double(value) }
    init(_ value: Bool) { self = .bool(value) }
    init(_ value: [JSONValue]) { self = .array(value) }
    init(_ value: [String: JSONValue]) { self = .object(value) }

    // Helper properties for type-safe access
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

    // MARK: - Equatable Conformance
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

    // MARK: - Hashable Conformance
    func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value):
            hasher.combine(value)
        case .int(let value):
            hasher.combine(value)
        case .double(let value):
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(value)
        case .array(let value):
            hasher.combine(value)
        case .object(let value):
            hasher.combine(value)
        case .null:
            hasher.combine(0) // A unique hash for null
        }
    }
}