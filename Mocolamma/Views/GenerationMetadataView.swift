import SwiftUI

struct GenerationMetadataRow {
    let title: String
    let value: String
}

struct GenerationMetadataSection {
    let title: String
    let rows: [GenerationMetadataRow]
}

struct GenerationMetadata {
    let summaryItems: [String]

    var summary: String { summaryItems.joined(separator: "  ") }
    let sections: [GenerationMetadataSection]
    var isGenerating = false
    var isStopped = false

    var canShowDetails: Bool { !isGenerating && !isStopped }
    var primarySummaryItemCount = 2

    var primarySummaryItems: ArraySlice<String> { summaryItems.prefix(primarySummaryItemCount) }
    var secondarySummaryItems: ArraySlice<String> { summaryItems.dropFirst(primarySummaryItemCount) }

    var copyText: String {
        sections.map { section in
            ([section.title] + section.rows.map { "\($0.title): \($0.value)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static var unknown: String { String(localized: "Unknown") }

    static func value(_ value: Int?) -> String { value.map { $0.formatted() } ?? unknown }

    static func tokenCount(_ count: Int?) -> String {
        count.map { String(localized: "\($0) Tokens") } ?? unknown
    }

    @MainActor
    static func message(_ message: ChatMessage) -> GenerationMetadata {
        let statistics = message.statistics
        let date = statistics.completedAt ?? message.createdAt.flatMap { MessageView.parseDate(from: $0) }
        let model = statistics.modelName ?? message.speechModelName ?? unknown
        let voice = message.speechVoice.map { $0 == "default" ? String(localized: "Default") : $0 } ?? unknown
        let duration = GenerationStatistics.formattedDuration(message.totalDuration)
        var basic = [
            GenerationMetadataRow(title: String(localized: "Generation Completed At"), value: GenerationStatistics.date(statistics.completedAt, detailed: true)),
            GenerationMetadataRow(title: String(localized: "Model"), value: model)
        ]
        let timing: [GenerationMetadataRow]
        let information: GenerationMetadataSection
        var summary: [String?] = [date.map { GenerationStatistics.date($0) }, statistics.modelName ?? message.speechModelName]
        let primaryItemCount = summary.compactMap { $0 }.count
        let knownDuration = message.totalDuration.flatMap { $0 >= 0 ? duration : nil }
        if message.isSpeechGeneration {
            basic.append(.init(title: String(localized: "Voice"), value: voice))
            summary += [message.speechVoice.map { $0 == "default" ? String(localized: "Default") : $0 }, knownDuration]
            timing = [.init(title: String(localized: "Response Time"), value: duration)]
            let length = message.speechPlayback?.duration?.generationDurationDescription ?? unknown
            information = .init(title: String(localized: "Audio Information"), rows: [
                .init(title: String(localized: "Length"), value: length)
            ])
        } else if message.isImageGeneration {
            summary.append(knownDuration)
            timing = [
                .init(title: String(localized: "Model Load Time"), value: GenerationStatistics.formattedDuration(statistics.loadDuration)),
                .init(title: String(localized: "Total Processing Time"), value: duration)
            ]
            let size: String
            if let width = statistics.imageWidth, let height = statistics.imageHeight {
                size = "\(width) × \(height) px"
            } else { size = unknown }
            information = .init(title: String(localized: "Image Information"), rows: [
                .init(title: String(localized: "Steps"), value: value(statistics.imageSteps)),
                .init(title: String(localized: "Image Size"), value: size)
            ])
        } else {
            let tokens = tokenCount(message.evalCount)
            let speed = GenerationStatistics.formattedTokenSpeed(
                GenerationStatistics.tokensPerSecond(count: message.evalCount, nanoseconds: message.evalDuration)
            )
            summary += [message.evalCount.flatMap { $0 >= 0 ? tokens : nil },
                        GenerationStatistics.tokensPerSecond(count: message.evalCount, nanoseconds: message.evalDuration).map { GenerationStatistics.formattedTokenSpeed($0) }]
            timing = [
                .init(title: String(localized: "Model Load Time"), value: GenerationStatistics.formattedDuration(statistics.loadDuration)),
                .init(title: String(localized: "Prefill Time"), value: GenerationStatistics.formattedDuration(statistics.promptEvalDuration)),
                .init(title: String(localized: "Prefill Speed"), value: GenerationStatistics.formattedTokenSpeed(statistics.prefillTokensPerSecond)),
                .init(title: String(localized: "Output Token Generation Time"), value: GenerationStatistics.formattedDuration(message.evalDuration)),
                .init(title: String(localized: "Output Speed"), value: speed),
                .init(title: String(localized: "Total Processing Time"), value: duration)
            ]
            information = .init(title: String(localized: "Token Information"), rows: [
                .init(title: String(localized: "Input Tokens"), value: tokenCount(statistics.promptEvalCount)),
                .init(title: String(localized: "Output Tokens"), value: tokenCount(message.evalCount)),
                .init(title: String(localized: "Cache Hit"), value: GenerationStatistics.cacheHit(input: statistics.promptEvalCount, cached: statistics.cachedTokenCount))
            ])
        }
        return .init(summaryItems: summary.compactMap { $0 }, sections: [
            .init(title: String(localized: "Basic Information"), rows: basic),
            .init(title: String(localized: "Processing Time"), rows: timing), information
        ], isGenerating: message.isStreaming, isStopped: message.isStopped, primarySummaryItemCount: primaryItemCount)
    }

    static func decisionProgress(startedAt: Date?, modelName: String?) -> GenerationMetadata {
        .init(summaryItems: [startedAt.map { GenerationStatistics.date($0) }, modelName].compactMap { $0 },
              sections: [], isGenerating: true)
    }

    static func decision(_ result: DecisionResponse, completedAt: Date?, elapsed: TimeInterval) -> GenerationMetadata {
        let time = GenerationStatistics.formattedDuration(seconds: elapsed)
        let primaryItems = [completedAt.map { GenerationStatistics.date($0) }, result.model].compactMap { $0 }
        return .init(summaryItems: primaryItems + [time], sections: [
            .init(title: String(localized: "Basic Information"), rows: [
                .init(title: String(localized: "Generation Completed At"), value: GenerationStatistics.date(completedAt, detailed: true)),
                .init(title: String(localized: "Model"), value: result.model)
            ]),
            .init(title: String(localized: "Processing Time"), rows: [
                .init(title: String(localized: "Response Time"), value: time)
            ]),
            .init(title: String(localized: "Token Information"), rows: [
                .init(title: String(localized: "Input Tokens"), value: tokenCount(result.usage.input_tokens)),
                .init(title: String(localized: "Cache Hit"), value: GenerationStatistics.cacheHit(input: result.usage.input_tokens, cached: result.prompt_eval_cached_count))
            ])
        ], primarySummaryItemCount: primaryItems.count)
    }
}

struct GenerationMetadataView: View {
    let metadata: GenerationMetadata
    var wrapsWhenNeeded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isPresented = false

    var body: some View {
        Group {
            if !metadata.canShowDetails {
                summaryContent
            } else {
                Button { isPresented = true } label: {
                    summaryContent
                }
                .buttonStyle(.plain)
                .help("Show generation statistics")
                .accessibilityHint("Show generation statistics")
                .popover(isPresented: $isPresented, arrowEdge: popoverArrowEdge) {
                    GenerationStatisticsPopover(metadata: metadata, usesFixedSize: usesFixedPopoverSize)
                }
            }
        }
        .onChange(of: metadata.canShowDetails) { _, canShowDetails in
            if !canShowDetails { isPresented = false }
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if !metadata.primarySummaryItems.isEmpty {
                        HStack(alignment: .center, spacing: 6) {
                            summaryLabels(for: metadata.primarySummaryItems)
                        }
                    }
                    if !metadata.secondarySummaryItems.isEmpty {
                        HStack(alignment: .center, spacing: 6) {
                            summaryLabels(for: metadata.secondarySummaryItems)
                        }
                    }
                }
                disclosureIndicator
            }
        } else if wrapsWhenNeeded {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) {
                    summaryLabels
                    disclosureIndicator
                }
                    .fixedSize(horizontal: true, vertical: false)
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) { summaryLabels }
                    disclosureIndicator
                }
            }
        } else {
            HStack(alignment: .center, spacing: 6) {
                summaryLabels
                disclosureIndicator
            }
        }
#else
        HStack(alignment: .center, spacing: 8) {
            summaryLabels
            disclosureIndicator
        }
#endif
    }

    private var usesFixedPopoverSize: Bool {
#if os(iOS)
        horizontalSizeClass != .compact && verticalSizeClass != .compact
#else
        true
#endif
    }

    private var popoverArrowEdge: Edge? {
#if os(macOS)
        .bottom
#else
        nil
#endif
    }

    @ViewBuilder
    private var disclosureIndicator: some View {
        if metadata.canShowDetails {
            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var summaryLabels: some View {
        summaryLabels(for: metadata.summaryItems[...])
    }

    private func summaryLabels(for items: ArraySlice<String>) -> some View {
        ForEach(items.indices, id: \.self) { index in
            Text(verbatim: items[index])
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

}

struct GenerationStatisticsPopover: View {
    let metadata: GenerationMetadata
    var usesFixedSize = true
    @State private var isCopied = false
    @State private var copyFeedbackID: UUID?
    private let detailFont: Font = .body

    var body: some View {
        Group {
#if os(macOS)
            if #available(macOS 26, *) {
                statisticsForm
                    .safeAreaBar(edge: .bottom, alignment: .center, spacing: 0) {
                        copyBar
                    }
            } else {
                VStack(spacing: 0) {
                    statisticsForm
                    Divider()
                    copyBar
                }
            }
#else
            statisticsForm
#endif
        }
#if os(macOS)
        .frame(width: 320)
        .frame(idealHeight: 400, maxHeight: 400)
#else
        .frame(width: usesFixedSize ? 400 : nil)
        .frame(idealHeight: usesFixedSize ? 500 : nil, maxHeight: usesFixedSize ? 500 : nil)
#endif
        .task(id: copyFeedbackID) {
            guard copyFeedbackID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            withAnimation(.spring()) {
                isCopied = false
            }
        }
    }

    private var statisticsForm: some View {
        Form {
            ForEach(metadata.sections.indices, id: \.self) { sectionIndex in
                let section = metadata.sections[sectionIndex]
                Section {
                    ForEach(section.rows.indices, id: \.self) { rowIndex in
                        let row = section.rows[rowIndex]
                        statisticsRow(row)
                    }
                } header: {
                    Text(verbatim: section.title)
                }
            }
#if !os(macOS)
            Section {
                copyStatisticsButton
            }
#endif
        }
        .formStyle(.grouped)
    }

    private var copyStatisticsButton: some View {
        Button {
            copy(metadata.copyText)
            withAnimation(.spring()) {
                isCopied = true
            }
            copyFeedbackID = UUID()
        } label: {
            Label {
                Text("Copy Statistics")
            } icon: {
                CopyFeedbackIcon(isCopied: isCopied)
            }
        }
        .help("Copy statistics as text")
    }

#if os(macOS)
    private var copyBar: some View {
        HStack {
            Spacer(minLength: 0)
            copyStatisticsButton
                .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
#endif

    private func statisticsRow(_ row: GenerationMetadataRow) -> some View {
        LabeledContent {
            Text(verbatim: row.value)
                .font(detailFont)
                .textSelection(.disabled)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: row.title)
                .font(detailFont)
                .foregroundStyle(.primary)
        }
        .textSelection(.disabled)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
#if canImport(UIKit)
        .overlay {
            CopyValueEditMenu(value: row.value)
                .accessibilityHidden(true)
        }
#else
        .contextMenu {
            if #available(macOS 26, *) {
                Button("Copy", systemImage: SFSymbol.copy) {
                    copy(row.value)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Button("Copy", systemImage: SFSymbol.copy) {
                    copy(row.value)
                }
            }
        }
#endif
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Copy")) {
            copy(row.value)
        }
    }

    private func copy(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
    }

}

#Preview("Chat Statistics") {
    let message = ChatMessage(role: "assistant", content: "", totalDuration: 3_000_000_000, evalCount: 40, evalDuration: 2_000_000_000)
    message.statistics = GenerationStatistics(completedAt: Date(), modelName: "example-model:8b", loadDuration: 500_000_000,
                                              promptEvalDuration: 500_000_000, promptEvalCount: 100, cachedTokenCount: 25)
    return GenerationStatisticsPopover(metadata: .message(message))
        .environment(\.locale, Locale(identifier: "ja"))
}

#Preview("Metadata Alignment") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .center, spacing: 8) {
            GenerationMetadataView(metadata: .init(summaryItems: ["2026/11/10 23:00:00", "example:8b", "40 Tokens", "20.00 Tok/s"], sections: []))
            Image(systemName: "arrow.clockwise").padding(5)
            Image(systemName: "doc.on.doc").padding(5)
            Image(systemName: "square.and.arrow.up").padding(5)
        }
        .font(.caption2)
        GenerationMetadataView(metadata: .init(summaryItems: ["2026/11/10 23:00:00", "example:8b", "3.097 s"], sections: []))
    }
    .padding()
}

#Preview("Streaming Metadata") {
    let message = ChatMessage(role: "assistant", content: "", createdAt: "2026-11-11T01:00:00Z", isStreaming: true)
    message.statistics.modelName = "example-model:8b"
    return GenerationMetadataView(metadata: .message(message))
        .padding()
}

#Preview("Compact Metadata") {
    VStack(alignment: .leading, spacing: 20) {
        GenerationMetadataView(metadata: .init(summaryItems: ["2026/11/11 10:00:00", "example:8b", "40 Tokens", "20.00 Tok/s"], sections: []))
        GenerationMetadataView(metadata: .init(summaryItems: ["2026/11/11 10:00:00", "example:8b"], sections: [], isGenerating: true))
    }
    .padding()
    .environment(\.horizontalSizeClass, .compact)
}
