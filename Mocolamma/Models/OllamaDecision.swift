import Foundation

struct DecisionOption: Identifiable, Equatable {
    var id = UUID()
    var text = ""
}

struct DecisionCondition: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case choice, noul, score
        var id: String { rawValue }
        var title: String {
            switch self {
            case .choice: String(localized: "Choice")
            case .noul: String(localized: "Yes / No")
            case .score: String(localized: "Score")
            }
        }
    }
    var id = UUID()
    var instructions = ""
    var kind: Kind = .choice
    var optionEntries: [DecisionOption] = [DecisionOption()]
    var isExpanded = true

    init(id: UUID = UUID(), instructions: String = "", kind: Kind = .choice, options: [String] = [""], isExpanded: Bool = true) {
        self.id = id
        self.instructions = instructions
        self.kind = kind
        self.optionEntries = options.map { DecisionOption(text: $0) }
        self.isExpanded = isExpanded
    }

    var options: [String] {
        get { optionEntries.map(\.text) }
        set {
            optionEntries = newValue.enumerated().map { index, text in
                DecisionOption(id: optionEntries.indices.contains(index) ? optionEntries[index].id : UUID(), text: text)
            }
        }
    }

    mutating func normalizeOptions() {
        let lastID = optionEntries.last?.id
        optionEntries.removeAll {
            $0.id != lastID && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if optionEntries.isEmpty || optionEntries.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            optionEntries.append(DecisionOption())
        }
    }

    @discardableResult
    mutating func moveOption(id: UUID, to destinationID: UUID) -> Bool {
        guard kind == .score, id != destinationID,
              let source = optionEntries.firstIndex(where: { $0.id == id }),
              let destination = optionEntries.firstIndex(where: { $0.id == destinationID }),
              !optionEntries[source].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !optionEntries[destination].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let option = optionEntries.remove(at: source)
        optionEntries.insert(option, at: destination)
        return true
    }

    var validOptions: [String] { options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    func resultOptions(probabilities: [String: Double]) -> [String] {
        guard kind == .choice else { return validOptions }
        return validOptions.enumerated().sorted { left, right in
            let leftProbability = probabilities[left.element] ?? 0
            let rightProbability = probabilities[right.element] ?? 0
            return leftProbability == rightProbability ? left.offset < right.offset : leftProbability > rightProbability
        }.map(\.element)
    }

    var hasDuplicateOptions: Bool { Set(validOptions).count != validOptions.count }
    var isValid: Bool {
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind == .noul { return true }
        let values = validOptions
        return values.count >= 2 && values.count <= (kind == .score ? 10 : 26) && !hasDuplicateOptions
    }
}

struct DecisionAnswer: Codable {
    let type: String
    let choice: String?
    let noul: Double?
    let score: Double?
    let legend: [String: String]?
    let probabilities: [String: Double]?
    let confidence: Double?
}

struct DecisionResponse: Codable {
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
    let model: String
    let answers: [String: DecisionAnswer]
    let usage: Usage
    var prompt_eval_cached_count: Int? = nil

    var cacheHitRate: Double? {
        guard let cached = prompt_eval_cached_count, usage.input_tokens > 0 else { return nil }
        return Double(cached) / Double(usage.input_tokens)
    }
}

enum DecisionResultFormatter {
    static func points(_ value: Int) -> String {
        value == 1 ? String(localized: "\(value) point") : String(localized: "\(value) points")
    }

    static func text(conditions: [DecisionCondition], response: DecisionResponse?) -> String {
        conditions.enumerated().compactMap { index, condition in
            guard let answer = response?.answers[condition.id.uuidString] else { return nil }
            let percent: (Double) -> String = { $0.formatted(.percent.precision(.fractionLength(0))) }
            let lines: [String]
            switch condition.kind {
            case .choice:
                let probabilities = answer.probabilities ?? [:]
                lines = condition.resultOptions(probabilities: probabilities).map { option in
                    "\(option) (\(percent(probabilities[option] ?? 0)))"
                }
            case .noul:
                guard let probability = answer.noul else { return nil }
                let isYes = probability >= 0.5
                let label = isYes ? String(localized: "Yes") : String(localized: "No")
                lines = ["\(label) (\(percent(isYes ? probability : 1 - probability)))"]
            case .score:
                guard let score = answer.score else { return nil }
                let maximum = max(0, condition.validOptions.count - 1)
                let summary = "\(score.formatted(.number.precision(.fractionLength(2)))) / \(points(maximum))"
                let probabilities = answer.probabilities ?? [:]
                lines = [summary, ""] + condition.validOptions.enumerated().map { offset, option in
                    "\(points(offset)) - \(option) - \(percent(probabilities[String(offset)] ?? 0))"
                }
            }
            return "\(index + 1). \(condition.instructions)\n\n\(lines.joined(separator: "\n"))"
        }.joined(separator: "\n\n---\n\n")
    }
}

enum DecisionRequestBuilder {
    static func state(text: String, json: Bool) throws -> JSONValue {
        if json {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            switch value {
            case .object, .array: return value
            default: throw DecisionError.invalidJSON
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DecisionError.emptyState }
        return .string(text)
    }

    static func body(model: String, state: JSONValue, images: [String], conditions: [DecisionCondition], keepAlive: JSONValue?) throws -> Data {
        guard !conditions.isEmpty, conditions.count <= 64, conditions.allSatisfy(\.isValid) else { throw DecisionError.invalidConditions }
        let encoder = JSONEncoder()
        func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        // 質問と選択肢の入力順を保ち、同率時の優先順位が変わらないようにする。
        var questions: [String] = []
        for condition in conditions {
            var fields = ["\"type\":\(try encode(condition.kind.rawValue))", "\"instructions\":\(try encode(condition.instructions))"]
            if condition.kind == .score {
                fields.append("\"criteria\":\(try encode(condition.validOptions))")
            } else if condition.kind == .choice {
                let options = try condition.validOptions.map { "\(try encode($0)):null" }.joined(separator: ",")
                fields.append("\"criteria\":{\(options)}")
            }
            questions.append("\(try encode(condition.id.uuidString)):{\(fields.joined(separator: ","))}")
        }
        var fields = ["\"model\":\(try encode(model))", "\"state\":\(try encode(state))", "\"questions\":{\(questions.joined(separator: ","))}"]
        if let keepAlive { fields.append("\"keep_alive\":\(try encode(keepAlive))") }
        let textBody = Data("{\(fields.joined(separator: ","))}".utf8)
        guard textBody.count <= 65_536 else { throw DecisionError.textTooLarge }
        if !images.isEmpty { fields.append("\"images\":\(try encode(images))") }
        let body = Data("{\(fields.joined(separator: ","))}".utf8)
        guard body.count <= 32 * 1024 * 1024 else { throw DecisionError.requestTooLarge }
        return body
    }
}

enum DecisionError: LocalizedError {
    case invalidJSON, emptyState, invalidConditions, textTooLarge, requestTooLarge, unsupportedAttachments
    case server(Int, String)
    var errorDescription: String? {
        switch self {
        case .unsupportedAttachments: String(localized: "The selected model or input mode does not support these attachments.")
        case .invalidJSON: String(localized: "Enter a valid JSON object or array.")
        case .emptyState: String(localized: "Enter content to evaluate.")
        case .invalidConditions: String(localized: "Enter each condition and at least two distinct options for choice or score questions.")
        case .textTooLarge: String(localized: "Decision text and conditions must fit within 64 KiB.")
        case .requestTooLarge: String(localized: "The decision request must fit within 32 MiB.")
        case .server(let status, let message): String(localized: "Decision request failed (HTTP \(status)): \(message)")
        }
    }
}
