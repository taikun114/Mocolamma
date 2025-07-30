
// OllamaChat.swift

import SwiftUI
import Foundation

// MARK: - Chat API Request/Response Models

/// Represents a single message in a chat conversation.
struct ChatMessage: Codable, Identifiable, Hashable {
    let id = UUID()
    var role: String
    var content: String
    var images: [String]? // Base64 encoded images
    var toolCalls: [ToolCall]?
    var toolName: String?
    var createdAt: String? // メッセージが作成された日時
    var totalDuration: Int? // 応答生成にかかった合計時間 (ナノ秒)
    var evalCount: Int? // 応答内のトークン数
    var evalDuration: Int? // 応答生成にかかった時間 (ナノ秒)
    var isStreaming: Bool = false // ストリーミング中かどうかを示すフラグ
    var isStopped: Bool = false // ストリーミングがユーザーによって停止されたかどうかを示すフラグ

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case images
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
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
    let options: ChatRequestOptions?
    let tools: [ToolDefinition]?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case options
        case tools
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
    let temperature: Double?
    let repeatPenalty: Double?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let penalizeNewline: Bool?
    let stop: [String]?
    let numa: Bool?
    let numCtx: Int?
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
