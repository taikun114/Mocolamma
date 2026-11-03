import Foundation
import Testing
@testable import Mocolamma

struct DecisionRequestTests {
    @Test @MainActor func imageOnlyInputRequiresVisionButTextOrFilesCanBeSentWithoutImages() {
        let textModel = OllamaModel(name: "text", model: "text", modifiedAt: "", size: 0, digest: "", details: nil, capabilities: ["decision"])
        let visionModel = OllamaModel(name: "vision", model: "vision", modifiedAt: "", size: 0, digest: "", details: nil, capabilities: ["decision", "vision"])
        let session = DecisionSession()
        session.selectedModelID = textModel.id
        session.conditions = [DecisionCondition(instructions: "Is this valid?", kind: .noul)]
        session.images = [ChatInputImage(data: Data([1]))]
        #expect(!session.canEvaluate(model: textModel))
        #expect(session.canEvaluate(model: visionModel))
        session.input = "Some text"
        #expect(session.canEvaluate(model: textModel))
        session.input = ""
        session.attachments = [ChatInputAttachment(name: "note.txt", content: "Some text")]
        #expect(session.canEvaluate(model: textModel))
        session.attachments = [ChatInputAttachment(name: "audio.m4a", content: "", audioData: Data([1]))]
        #expect(!session.canEvaluate(model: textModel))
    }
    @Test func resultTextIncludesProbabilitiesAndScoreLevels() {
        let choice = DecisionCondition(instructions: "Classify", options: ["A", "B"])
        let yesNo = DecisionCondition(instructions: "Is it valid?", kind: .noul)
        let score = DecisionCondition(instructions: "Rate", kind: .score, options: ["Low", "High"])
        let response = DecisionResponse(model: "test", answers: [
            choice.id.uuidString: DecisionAnswer(type: "choice", choice: "B", noul: nil, score: nil, legend: nil, probabilities: ["A": 0.2, "B": 0.8], confidence: nil),
            yesNo.id.uuidString: DecisionAnswer(type: "noul", choice: nil, noul: 0.2, score: nil, legend: nil, probabilities: nil, confidence: nil),
            score.id.uuidString: DecisionAnswer(type: "score", choice: nil, noul: nil, score: 0.75, legend: nil, probabilities: ["0": 0.25, "1": 0.75], confidence: nil)
        ], usage: .init(input_tokens: 1, output_tokens: 0))
        let text = DecisionResultFormatter.text(conditions: [choice, yesNo, score], response: response)
        #expect(text.contains("B (80%)\nA (20%)"))
        #expect(text.contains("\n\n---\n\n2. Is it valid?\n\n\(String(localized: "No")) (80%)"))
        #expect(text.contains("0.75 / \(DecisionResultFormatter.points(1))\n\n\(DecisionResultFormatter.points(0)) - Low - 25%\n\(DecisionResultFormatter.points(1)) - High - 75%"))
    }
    @Test func resultJSONIncludesConditionsAndAnswersWithoutStatistics() throws {
        let choice = DecisionCondition(instructions: "Classify this report", options: ["Bug", "Request", ""])
        let score = DecisionCondition(instructions: "Rate severity", kind: .score, options: ["Low", "High"])
        let yesNo = DecisionCondition(instructions: "Is this valid?", kind: .noul)
        let missing = DecisionCondition(instructions: "Unanswered", kind: .noul)
        let response = DecisionResponse(model: "sample-model", answers: [
            choice.id.uuidString: DecisionAnswer(type: "choice", choice: "Bug", noul: nil, score: nil, legend: nil, probabilities: ["Bug": 0.9, "Request": 0.1], confidence: nil),
            score.id.uuidString: DecisionAnswer(type: "score", choice: nil, noul: nil, score: 0.8, legend: ["0": "Low", "1": "High"], probabilities: ["0": 0.2, "1": 0.8], confidence: nil),
            yesNo.id.uuidString: DecisionAnswer(type: "noul", choice: nil, noul: 0.7, score: nil, legend: nil, probabilities: nil, confidence: nil)
        ], usage: .init(input_tokens: 123, output_tokens: 0), prompt_eval_cached_count: 12)
        let text = DecisionResultFormatter.json(conditions: [choice, score, yesNo, missing], response: response)
        let rows = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        #expect(rows.count == 3)
        #expect(rows.map { $0["condition"] as? String } == [choice.instructions, score.instructions, yesNo.instructions])
        #expect(Set(rows[0].keys) == ["condition", "type", "options", "result"])
        #expect(rows[0]["options"] as? [String] == ["Bug", "Request"])
        #expect(rows[1]["options"] as? [String] == ["Low", "High"])
        #expect(rows[2]["options"] == nil)
        #expect(rows.map { $0["type"] as? String } == ["choice", "score", "noul"])
        let answers = try rows.map { try #require($0["result"] as? [String: Any]) }
        #expect(answers.allSatisfy { $0["type"] == nil })
        #expect(answers[0]["choice"] as? String == "Bug")
        #expect((answers[0]["probabilities"] as? [String: Double])?["Bug"] == 0.9)
        #expect(answers[1]["score"] as? Double == 0.8)
        #expect((answers[1]["legend"] as? [String: String])?["1"] == "High")
        #expect(answers[2]["noul"] as? Double == 0.7)
        #expect(DecisionResultFormatter.json(conditions: [choice], response: nil).isEmpty)
    }

    @Test func preservesStructuredJSON() throws {
        let state = try DecisionRequestBuilder.state(text: "{\"count\":2,\"enabled\":true}", json: true)
        let question = DecisionCondition(instructions: "Is this valid?", kind: .noul)
        let data = try DecisionRequestBuilder.body(model: "d3:2b", state: state, images: [], conditions: [question], keepAlive: .int(0))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = try #require(object["state"] as? [String: Any])
        #expect(value["count"] as? Int == 2)
        #expect(value["enabled"] as? Bool == true)
        #expect(object["stream"] == nil)
        #expect(object["keep_alive"] as? Int == 0)
    }
    @Test func rejectsMalformedAndScalarJSON() {
        for text in ["{", "true", "42", "\"hello\""] {
            #expect(throws: (any Error).self) { try DecisionRequestBuilder.state(text: text, json: true) }
        }
    }
    @Test func validatesConditionsWithoutClientSizeLimit() throws {
        #expect(!DecisionCondition().isValid)
        #expect(!DecisionCondition(instructions: "Choose", options: ["same", "same"]).isValid)
        #expect(DecisionCondition(instructions: "Choose", options: ["a", "b", ""]).isValid)
        let q = DecisionCondition(instructions: "Rate", kind: .score, options: ["Low", "High"])
        let data = try DecisionRequestBuilder.body(model: "sample-model", state: .string(String(repeating: "a", count: 65_536)), images: [], conditions: [q], keepAlive: nil)
        #expect(data.count > 65_536)
    }

    @Test @MainActor func allowsMoreThan64ValidConditions() throws {
        let conditions = (0..<65).map { DecisionCondition(instructions: "Condition \($0)", kind: .noul) }
        let data = try DecisionRequestBuilder.body(model: "sample-model", state: .string("Sample input"), images: [], conditions: conditions, keepAlive: nil)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["questions"] as? [String: Any])?.count == 65)
        let session = DecisionSession()
        session.input = "Sample input"
        session.selectedModelID = "sample-model"
        session.conditions = conditions
        #expect(session.canEvaluate)
    }

    @Test func allowsImagePayloadOver32MiB() throws {
        let image = String(repeating: "A", count: 32 * 1024 * 1024)
        let q = DecisionCondition(instructions: "Inspect the image", kind: .noul)
        let data = try DecisionRequestBuilder.body(model: "sample-model", state: .string("Sample input"), images: [image], conditions: [q], keepAlive: nil)
        #expect(data.count > 32 * 1024 * 1024)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["images"] as? [String])?.first == image)
    }
    @Test @MainActor func duplicateLabelsBlockRequestsAndEvaluation() throws {
        for kind in [DecisionCondition.Kind.choice, .score] {
        let duplicate = DecisionCondition(instructions: "Classify the sample", kind: kind, options: ["Level A", " Level A ", ""])
        #expect(duplicate.hasDuplicateOptions)
        #expect(!duplicate.isValid)
        #expect(throws: DecisionError.self) {
            try DecisionRequestBuilder.body(model: "sample-model", state: .string("Sample input"), images: [], conditions: [duplicate], keepAlive: nil)
        }
        let session = DecisionSession()
        session.input = "Sample input"
        session.selectedModelID = "sample-model"
        session.conditions = [duplicate]
        #expect(!session.canEvaluate)
        session.conditions[0].options = ["Level A", "Level B", ""]
        #expect(!session.conditions[0].hasDuplicateOptions)
        #expect(session.canEvaluate)
        }
    }

    @Test func movingScoreOptionsPreservesRowIdentityAndTrailingInput() {
        var condition = DecisionCondition(instructions: "Rate the sample", kind: .score, options: ["Low", "Medium", "High", ""])
        let ids = condition.optionEntries.map(\.id)
        let moved = condition.moveOption(id: ids[0], to: ids[2])
        #expect(moved)
        #expect(condition.options == ["Medium", "High", "Low", ""])
        #expect(condition.optionEntries.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
        let movedIntoEmptyRow = condition.moveOption(id: ids[0], to: ids[3])
        #expect(!movedIntoEmptyRow)
        let movedUnknownRow = condition.moveOption(id: UUID(), to: ids[1])
        #expect(!movedUnknownRow)
        condition.optionEntries[3].text = "Extreme"
        condition.normalizeOptions()
        #expect(condition.optionEntries[3].id == ids[3])
        #expect(condition.options == ["Medium", "High", "Low", "Extreme", ""])
        condition.normalizeOptions()
        #expect(condition.optionEntries.count == 5)
    }

    @Test func clearingOptionTextRemovesExtraEmptyRowsAndPreservesOtherIDs() {
        var condition = DecisionCondition(instructions: "Choose", options: ["Alpha", "Beta", "Gamma", ""])
        let ids = condition.optionEntries.map(\.id)
        condition.optionEntries[1].text = ""
        condition.normalizeOptions()
        #expect(condition.options == ["Alpha", "Gamma", ""])
        #expect(condition.optionEntries.map(\.id) == [ids[0], ids[2], ids[3]])
        condition.optionEntries[0].text = " "
        condition.optionEntries[1].text = ""
        condition.normalizeOptions()
        #expect(condition.options == [""])
        #expect(condition.optionEntries[0].id == ids[3])
        condition.optionEntries[0].text = "Delta"
        condition.normalizeOptions()
        #expect(condition.options == ["Delta", ""])
        #expect(condition.optionEntries[0].id == ids[3])
    }

    @Test func choiceResultsSortByProbabilityAndKeepTiesStable() {
        var condition = DecisionCondition(instructions: "Choose", options: ["Alpha", "Beta", "Gamma", "Delta", ""])
        let probabilities = ["Alpha": 0.1, "Beta": 0.4, "Gamma": 0.4, "Delta": 0.1]
        #expect(condition.resultOptions(probabilities: probabilities) == ["Beta", "Gamma", "Alpha", "Delta"])
        #expect(condition.resultOptions(probabilities: [:]) == ["Alpha", "Beta", "Gamma", "Delta"])
        condition.kind = .score
        #expect(condition.resultOptions(probabilities: probabilities) == ["Alpha", "Beta", "Gamma", "Delta"])
    }

    @Test func preservesOptionOrder() throws {
        let q = DecisionCondition(instructions: "Rate", kind: .score, options: ["Low", "Middle", "High"])
        let data = try DecisionRequestBuilder.body(model: "d3:2b", state: .string("test"), images: [], conditions: [q], keepAlive: nil)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try #require(root["questions"] as? [String: [String: Any]])
        #expect(questions[q.id.uuidString]?["criteria"] as? [String] == ["Low", "Middle", "High"])
    }
    @Test func decodesProbabilitiesWithoutRounding() throws {
        let data = Data(#"{"model":"d3:2b","answers":{"a":{"type":"noul","noul":0.83},"b":{"type":"score","score":1.28,"legend":{"0":"Low","1":"High"},"probabilities":{"0":0.2,"1":0.8},"confidence":0.4}},"usage":{"input_tokens":40,"output_tokens":0}}"#.utf8)
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)
        #expect(response.answers["a"]?.noul == 0.83)
        #expect(response.answers["b"]?.score == 1.28)
    }
    @Test func readsAPITokenCountsAndCalculatesCacheHitRate() throws {
        let data = Data(#"{"model":"sample-model","answers":{},"usage":{"input_tokens":3124,"output_tokens":0},"prompt_eval_cached_count":254}"#.utf8)
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)
        #expect(response.usage.input_tokens == 3124)
        #expect(response.prompt_eval_cached_count == 254)
        #expect(response.cacheHitRate == Double(254) / 3124)
        var zero = DecisionResponse(model: "sample-model", answers: [:], usage: .init(input_tokens: 0, output_tokens: 0), prompt_eval_cached_count: 0)
        #expect(zero.cacheHitRate == nil)
        zero.prompt_eval_cached_count = nil
        #expect(zero.cacheHitRate == nil)
        let uncached = Data(#"{"model":"sample-model","answers":{},"usage":{"input_tokens":100,"output_tokens":0},"prompt_eval_cached_count":0}"#.utf8)
        #expect(try JSONDecoder().decode(DecisionResponse.self, from: uncached).cacheHitRate == 0)
        let missing = Data(#"{"model":"sample-model","answers":{},"usage":{"input_tokens":100,"output_tokens":0}}"#.utf8)
        #expect(try JSONDecoder().decode(DecisionResponse.self, from: missing).prompt_eval_cached_count == nil)
    }

    @Test @MainActor func resetClearsDraftAndResultsWithoutChangingModel() {
        let session = DecisionSession()
        session.selectedModelID = "d3:2b"
        session.input = "{}"
        session.isJSON = true
        session.conditions = [DecisionCondition(instructions: "Check", kind: .noul)]
        session.images = [ChatInputImage(data: Data([1]))]
        session.attachments = [ChatInputAttachment(name: "note.txt", content: "note")]
        session.reset()
        #expect(session.input.isEmpty)
        #expect(!session.isJSON)
        #expect(session.images.isEmpty && session.attachments.isEmpty)
        #expect(session.conditions.count == 1 && !session.conditions[0].isValid)
        #expect(session.selectedModelID == "d3:2b")
        #expect(!session.canEvaluate)
        #expect(!session.hasDraft)
    }
    @Test @MainActor func invalidJSONAndLoadingAttachmentsBlockEvaluation() {
        let session = DecisionSession()
        session.selectedModelID = "d3:2b"
        session.conditions = [DecisionCondition(instructions: "Check", kind: .noul)]
        session.input = "{"
        session.isJSON = true
        #expect(!session.canEvaluate)
        session.input = "{}"
        #expect(session.canEvaluate)
        session.images = [ChatInputImage(isLoading: true)]
        #expect(!session.canEvaluate)
    }

}
