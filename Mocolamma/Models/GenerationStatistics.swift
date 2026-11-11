import Foundation

struct GenerationStatistics: Equatable {
    var completedAt: Date?
    var modelName: String?
    var loadDuration: Int?
    var promptEvalDuration: Int?
    var promptEvalCount: Int?
    var cachedTokenCount: Int?
    var imageSteps: Int?
    var imageWidth: Int?
    var imageHeight: Int?

    var prefillTokensPerSecond: Double? {
        guard let count = promptEvalCount, let cached = cachedTokenCount,
              cached >= 0, cached <= count else { return nil }
        return Self.tokensPerSecond(count: count - cached, nanoseconds: promptEvalDuration)
    }

    static func tokensPerSecond(count: Int?, nanoseconds: Int?) -> Double? {
        guard let count, count >= 0, let nanoseconds, nanoseconds > 0 else { return nil }
        return Double(count) / (Double(nanoseconds) / 1_000_000_000)
    }

    static func formattedTokenSpeed(_ speed: Double?) -> String {
        guard let speed, speed.isFinite, speed >= 0 else { return String(localized: "Unknown") }
        return speed.formatted(.number.precision(.fractionLength(2))) + " Tok/s"
    }

    static func formattedDuration(_ nanoseconds: Int?) -> String {
        guard let nanoseconds else { return String(localized: "Unknown") }
        return formattedDuration(seconds: Double(nanoseconds) / 1_000_000_000)
    }

    static func formattedDuration(seconds: Double?) -> String {
        seconds?.generationDurationDescription ?? String(localized: "Unknown")
    }

    static func cacheHit(input: Int?, cached: Int?) -> String {
        guard let input, input > 0, let cached, cached >= 0 else { return String(localized: "Unknown") }
        let rate = (Double(cached) / Double(input)).formatted(.percent.precision(.fractionLength(2)))
        return String(localized: "\(rate) (\(cached) tokens)")
    }

    static func date(_ date: Date?, detailed: Bool = false) -> String {
        guard let date else { return String(localized: "Unknown") }
        let formatter = DateFormatter()
        formatter.dateStyle = detailed ? .medium : .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

extension ChatMessage {
    func updateGenerationStatistics(from chunk: ChatResponseChunk) {
        if !chunk.model.isEmpty { statistics.modelName = chunk.model }
        if let value = chunk.loadDuration { statistics.loadDuration = value }
        if let value = chunk.promptEvalDuration { statistics.promptEvalDuration = value }
        if let value = chunk.promptEvalCount { statistics.promptEvalCount = value }
        if let value = chunk.promptEvalCachedCount { statistics.cachedTokenCount = value }
        if let value = chunk.totalDuration { totalDuration = value }
        if let value = chunk.evalCount { evalCount = value }
        if let value = chunk.evalDuration { evalDuration = value }
    }
}
