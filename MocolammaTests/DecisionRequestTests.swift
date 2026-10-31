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
    @Test func validatesConditionsAndLimits() throws {
        #expect(!DecisionCondition().isValid)
        #expect(!DecisionCondition(instructions: "Choose", options: ["same", "same"]).isValid)
        #expect(DecisionCondition(instructions: "Choose", options: ["a", "b", ""]).isValid)
        let q = DecisionCondition(instructions: "Rate", kind: .score, options: ["Low", "High"])
        #expect(throws: DecisionError.self) {
            try DecisionRequestBuilder.body(model: "d3:2b", state: .string(String(repeating: "a", count: 65_536)), images: [], conditions: [q], keepAlive: nil)
        }
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
