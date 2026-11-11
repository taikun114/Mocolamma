import Foundation
import Testing
@testable import Mocolamma

struct GenerationStatisticsTests {
    @Test func decodesOptionalCacheStatistics() throws {
        let data = Data(#"{"model":"example","created_at":"2026-11-10T01:00:00Z","done":true,"prompt_eval_count":100,"prompt_eval_cached_count":25,"load_duration":1234567}"#.utf8)
        let chunk = try JSONDecoder().decode(ChatResponseChunk.self, from: data)
        #expect(chunk.promptEvalCachedCount == 25)
        #expect(chunk.loadDuration == 1234567)
        let legacy = Data(#"{"model":"example","created_at":"2026-11-10T01:00:00Z","done":true}"#.utf8)
        #expect(try JSONDecoder().decode(ChatResponseChunk.self, from: legacy).promptEvalCachedCount == nil)
    }

    @Test func handlesMissingAndZeroStatistics() {
        #expect(GenerationStatistics.formattedDuration(nil) == String(localized: "Unknown"))
        #expect(GenerationStatistics.cacheHit(input: 0, cached: 0) == String(localized: "Unknown"))
        #expect(GenerationStatistics.cacheHit(input: 100, cached: nil) == String(localized: "Unknown"))
        #expect(GenerationStatistics.formattedDuration(1_234_567) == GenerationStatistics.formattedDuration(seconds: 0.001234567))
        #expect(GenerationStatistics.cacheHit(input: 100, cached: 0) != String(localized: "Unknown"))
    }

    @Test func durationSwitchesToSecondsAboveOneThousandMilliseconds() {
        #expect(GenerationStatistics.formattedDuration(999_000_000) == String(localized: "\(999.0.formatted(.number.precision(.fractionLength(2)))) ms"))
        #expect(GenerationStatistics.formattedDuration(1_000_000_000) == String(localized: "\(1000.0.formatted(.number.precision(.fractionLength(2)))) ms"))
        #expect(GenerationStatistics.formattedDuration(1_000_000_001) == String(localized: "\(1.0.formatted(.number.precision(.fractionLength(3)))) s"))
        #expect(GenerationStatistics.formattedDuration(3_097_000_000) == String(localized: "\(3.097.formatted(.number.precision(.fractionLength(3)))) s"))
    }

    @Test func durationUsesMinutesAndHoursWithoutFractionalSeconds() {
        func unit(_ key: String.LocalizationValue, _ value: Int) -> String {
            String.localizedStringWithFormat(String(localized: key), value)
        }
        #expect(60.0.generationDurationDescription == unit("%dm", 1) + unit("%ds", 0))
        #expect(83.999.generationDurationDescription == unit("%dm", 1) + unit("%ds", 23))
        #expect(3599.999.generationDurationDescription == unit("%dm", 59) + unit("%ds", 59))
        #expect(3600.0.generationDurationDescription == unit("%dh", 1) + unit("%dm", 0) + unit("%ds", 0))
        #expect(5025.0.generationDurationDescription == unit("%dh", 1) + unit("%dm", 23) + unit("%ds", 45))
        #expect(Double.infinity.generationDurationDescription == String(localized: "Unknown"))
        #expect((-1.0).generationDurationDescription == String(localized: "Unknown"))
        #expect(Double.greatestFiniteMagnitude.generationDurationDescription == String(localized: "Unknown"))
    }

    @Test func tokenSpeedsExcludeCachedInputAndRejectMissingOrInvalidMeasurements() {
        var statistics = GenerationStatistics(promptEvalDuration: 500_000_000, promptEvalCount: 100, cachedTokenCount: 25)
        #expect(statistics.prefillTokensPerSecond == 150)
        statistics.cachedTokenCount = 100
        #expect(statistics.prefillTokensPerSecond == 0)
        statistics.cachedTokenCount = nil
        #expect(statistics.prefillTokensPerSecond == nil)
        statistics.cachedTokenCount = 101
        #expect(statistics.prefillTokensPerSecond == nil)
        #expect(GenerationStatistics.tokensPerSecond(count: 40, nanoseconds: 2_000_000_000) == 20)
        #expect(GenerationStatistics.tokensPerSecond(count: 40, nanoseconds: 0) == nil)
        #expect(GenerationStatistics.tokensPerSecond(count: nil, nanoseconds: 1) == nil)
        #expect(GenerationStatistics.tokensPerSecond(count: -1, nanoseconds: 1) == nil)
        #expect(GenerationStatistics.formattedTokenSpeed(nil) == String(localized: "Unknown"))
    }

    @Test @MainActor func speechRevisionKeepsCompletionAndModel() {
        let first = ChatMessage(role: "assistant", content: "first")
        first.isSpeechGeneration = true
        first.statistics = GenerationStatistics(completedAt: Date(timeIntervalSince1970: 1), modelName: "first")
        let latest = ChatMessage(role: "assistant", content: "latest")
        latest.isSpeechGeneration = true
        latest.statistics = GenerationStatistics(completedAt: Date(timeIntervalSince1970: 2), modelName: "latest")
        latest.revisions = first.speechRevisionsForRetry()
        latest.currentRevisionIndex = 1
        latest.selectSpeechRevision(at: 0)
        #expect(latest.statistics == first.statistics)
        latest.selectSpeechRevision(at: 1)
        #expect(latest.statistics.modelName == "latest")
        #expect(latest.statistics.completedAt == Date(timeIntervalSince1970: 2))
    }

    @Test @MainActor func detailsAndCopyUseTheSameOrderedStatistics() {
        let message = ChatMessage(role: "assistant", content: "result", evalCount: 40, evalDuration: 2_000_000_000)
        message.totalDuration = 3_000_000_000
        message.statistics = GenerationStatistics(completedAt: Date(timeIntervalSince1970: 1), modelName: "original-model",
                                                  loadDuration: 500_000_000, promptEvalDuration: 500_000_000,
                                                  promptEvalCount: 100, cachedTokenCount: 25)
        let metadata = GenerationMetadata.message(message)
        #expect(metadata.sections.map { $0.rows.count } == [2, 6, 3])
        #expect(metadata.sections[0].rows[1].value == "original-model")
        #expect(metadata.sections[1].rows[2].title == String(localized: "Prefill Speed"))
        #expect(metadata.sections[1].rows[2].value == GenerationStatistics.formattedTokenSpeed(150))
        #expect(metadata.sections[1].rows[4].title == String(localized: "Output Speed"))
        #expect(metadata.sections[1].rows[4].value == GenerationStatistics.formattedTokenSpeed(20))
        #expect(metadata.copyText.contains(String(localized: "Prefill Speed") + ": " + GenerationStatistics.formattedTokenSpeed(150)))
        #expect(metadata.copyText.contains(String(localized: "Output Speed") + ": " + GenerationStatistics.formattedTokenSpeed(20)))
        #expect(metadata.sections[1].rows[5].value == GenerationStatistics.formattedDuration(3_000_000_000))
        #expect(metadata.sections[2].rows[0].value == String(localized: "\(100) Tokens"))
        #expect(metadata.sections[2].rows[1].value == String(localized: "\(40) Tokens"))
        #expect(metadata.sections[2].rows[2].value == GenerationStatistics.cacheHit(input: 100, cached: 25))
        #expect(metadata.copyText.contains("original-model"))
        #expect(metadata.summary.contains(20.0.formatted(.number.precision(.fractionLength(2))) + " Tok/s"))
        #expect(metadata.copyText.components(separatedBy: "\n\n").count == 3)
    }

    @Test @MainActor func missingResultsNeverUseCurrentTimeOrInventCacheHits() {
        let message = ChatMessage(role: "assistant", content: "legacy")
        let metadata = GenerationMetadata.message(message)
        #expect(metadata.summaryItems.isEmpty)
        #expect(metadata.sections.flatMap(\.rows).allSatisfy { $0.value == String(localized: "Unknown") })
        message.isImageGeneration = true
        #expect(GenerationMetadata.message(message).sections.map { $0.rows.count } == [2, 2, 2])
        message.isImageGeneration = false
        message.isSpeechGeneration = true
        #expect(GenerationMetadata.message(message).sections.map { $0.rows.count } == [3, 1, 1])
    }

    @Test @MainActor func streamingSummaryShowsCreationDateAndOnlyAvailableValues() throws {
        let message = ChatMessage(role: "assistant", content: "", createdAt: "2026-11-11T01:00:00Z", isStreaming: true)
        let date = try #require(MessageView.parseDate(from: "2026-11-11T01:00:00Z"))
        var metadata = GenerationMetadata.message(message)
        #expect(metadata.isGenerating)
        #expect(metadata.summaryItems == [GenerationStatistics.date(date)])
        #expect(metadata.sections[0].rows[0].value == String(localized: "Unknown"))
        let data = Data(#"{"model":"received-model","created_at":"2026-11-11T01:00:01Z","done":false,"eval_count":12,"eval_duration":500000000}"#.utf8)
        let chunk = try JSONDecoder().decode(ChatResponseChunk.self, from: data)
        message.updateGenerationStatistics(from: chunk)
        metadata = GenerationMetadata.message(message)
        #expect(metadata.isGenerating)
        #expect(metadata.summaryItems == [GenerationStatistics.date(date), "received-model", String(localized: "\(12) Tokens"), GenerationStatistics.formattedTokenSpeed(24)])
        message.isStreaming = false
        message.statistics.completedAt = date.addingTimeInterval(2)
        #expect(!GenerationMetadata.message(message).isGenerating)
        #expect(GenerationMetadata.message(message).summaryItems[0] == GenerationStatistics.date(date.addingTimeInterval(2)))
    }

    @Test @MainActor func partialStatisticsSurviveChunksWithoutMeasurements() throws {
        let message = ChatMessage(role: "assistant", content: "", isStreaming: true)
        message.statistics = GenerationStatistics(modelName: "known-model", promptEvalCount: 100)
        message.evalCount = 12
        message.evalDuration = 500_000_000
        let data = Data(#"{"model":"known-model","created_at":"2026-11-11T01:00:01Z","done":false}"#.utf8)
        message.updateGenerationStatistics(from: try JSONDecoder().decode(ChatResponseChunk.self, from: data))
        #expect(message.statistics.promptEvalCount == 100)
        #expect(message.evalCount == 12)
        #expect(message.evalDuration == 500_000_000)
        #expect(!GenerationMetadata.message(message).summaryItems.contains(String(localized: "Unknown")))
        message.isImageGeneration = true
        #expect(GenerationMetadata.message(message).summaryItems == ["known-model"])
        message.isImageGeneration = false
        message.isSpeechGeneration = true
        message.speechVoice = "default"
        #expect(GenerationMetadata.message(message).summaryItems == ["known-model", String(localized: "Default")])
    }

    @Test func decisionProgressDoesNotExposePreviousResultDetails() {
        let date = Date(timeIntervalSince1970: 1)
        let metadata = GenerationMetadata.decisionProgress(startedAt: date, modelName: "new-model")
        #expect(metadata.isGenerating)
        #expect(metadata.sections.isEmpty)
        #expect(metadata.summaryItems == [GenerationStatistics.date(date), "new-model"])
    }

    @Test @MainActor func compactSummaryKeepsDatesAndModelsSeparateFromOtherValues() {
        let message = ChatMessage(role: "assistant", content: "", evalCount: 40, evalDuration: 2_000_000_000)
        message.statistics.modelName = "known-model"
        var metadata = GenerationMetadata.message(message)
        #expect(Array(metadata.primarySummaryItems) == ["known-model"])
        #expect(Array(metadata.secondarySummaryItems) == [String(localized: "\(40) Tokens"), GenerationStatistics.formattedTokenSpeed(20)])
        let date = Date(timeIntervalSince1970: 1)
        message.statistics.completedAt = date
        metadata = GenerationMetadata.message(message)
        #expect(Array(metadata.primarySummaryItems) == [GenerationStatistics.date(date), "known-model"])
        #expect(metadata.secondarySummaryItems.count == 2)
        message.isSpeechGeneration = true
        message.speechVoice = "default"
        metadata = GenerationMetadata.message(message)
        #expect(Array(metadata.secondarySummaryItems) == [String(localized: "Default")])
        let response = DecisionResponse(model: "decision", answers: [:], usage: .init(input_tokens: 1, output_tokens: 0))
        let decision = GenerationMetadata.decision(response, completedAt: nil, elapsed: 1)
        #expect(Array(decision.primarySummaryItems) == ["decision"])
        #expect(Array(decision.secondarySummaryItems) == [GenerationStatistics.formattedDuration(seconds: 1)])
    }

    @Test @MainActor func stoppedMetadataKeepsStreamingSummaryAndCannotOpenDetails() {
        let message = ChatMessage(role: "assistant", content: "partial", createdAt: "2026-11-11T01:00:00Z", evalCount: 12, evalDuration: 500_000_000, isStreaming: true)
        message.statistics.modelName = "known-model"
        let streaming = GenerationMetadata.message(message)
        #expect(!streaming.canShowDetails)
        message.isStreaming = false
        message.isStopped = true
        let stopped = GenerationMetadata.message(message)
        #expect(stopped.summaryItems == streaming.summaryItems)
        #expect(!stopped.canShowDetails)
        message.isStopped = false
        #expect(GenerationMetadata.message(message).canShowDetails)
    }

    @Test func decisionDetailsIncludeInputAndCacheOnly() {
        let response = DecisionResponse(model: "decision-model", answers: [:], usage: .init(input_tokens: 80, output_tokens: 0), prompt_eval_cached_count: 20)
        let metadata = GenerationMetadata.decision(response, completedAt: Date(timeIntervalSince1970: 1), elapsed: 0.12345)
        #expect(metadata.sections.map { $0.rows.count } == [2, 1, 2])
        #expect(metadata.sections[1].rows[0].value == GenerationStatistics.formattedDuration(seconds: 0.12345))
        #expect(metadata.sections[2].rows[0].value == String(localized: "\(80) Tokens"))
        #expect(metadata.sections[2].rows[1].value == GenerationStatistics.cacheHit(input: 80, cached: 20))
    }

}
