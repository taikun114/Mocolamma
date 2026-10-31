import SwiftUI
import UniformTypeIdentifiers

private enum DecisionScoreDrag {
    static let contentType = UTType(exportedAs: "design.taikun.Mocolamma.decision-score-reorder", conformingTo: .data)

    static func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: contentType.identifier, visibility: .ownProcess) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }
}

struct DecisionConditionEditor: View {
    @Binding var condition: DecisionCondition
    let number: Int
    let onDelete: () -> Void
    @State private var draggingOption: UUID?
    @State private var optionRowWidth: CGFloat = 0
    @FocusState private var focusedOptionID: UUID?
    @ScaledMetric(relativeTo: .body) private var disclosureWidth = 16
#if os(iOS)
    @ScaledMetric(relativeTo: .body) private var scoreRowHeight = 46
    @ScaledMetric(relativeTo: .body) private var scoreRowInset = 6
#else
    @ScaledMetric(relativeTo: .body) private var scoreRowHeight = 56
#endif

    private var kindPicker: some View {
        Picker("Decision Type", selection: $condition.kind) {
            ForEach(DecisionCondition.Kind.allCases) { kind in Text(kind.title).tag(kind) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { condition.isExpanded.toggle() }
            } label: {
                HStack {
                    Text("\(number).")
                    if condition.instructions.isEmpty {
                        Text("Decision Condition").foregroundStyle(.secondary)
                    } else { Text(condition.instructions).lineLimit(1) }
                    Spacer()
                    Text(condition.kind.title).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: condition.isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: disclosureWidth)
                }
                .padding(.vertical, 12)
#if os(iOS)
                .frame(minHeight: 52)
#endif
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand or collapse this condition")
            .accessibilityValue(condition.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            if condition.isExpanded {
                Divider().padding(.horizontal, -16)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                    Text("Decision Condition")
                    TextField("Decision Condition", text: $condition.instructions, prompt: Text("Enter a condition…"), axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .modifier(DecisionInputStyle())
                        .accessibilityIdentifier("decision_condition_\(number)")
                    }
                    .padding(.vertical, 12)
                    Divider()
                    Group {
#if os(macOS)
                    AdaptiveSegmentedPickerRow(title: "Decision Type") {
                        kindPicker
                    }
#else
                    HStack {
                        Text("Decision Type")
                        Spacer()
                        kindPicker
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
#endif
                    }
                    .padding(.vertical, 12)
                    if condition.kind != .noul {
                        Divider()
#if os(macOS)
                        optionRows
#else
                        if condition.kind == .score {
                            nativeScoreOptions
#if os(iOS)
                                .padding(.top, max(0, 12 - scoreRowInset))
                                .padding(.bottom, -scoreRowInset)
#else
                                .padding(.top, 12)
#endif
                        } else {
                            optionRows
                        }
#endif
                        if condition.hasDuplicateOptions || condition.validOptions.count < 2 {
                            Text("At least two unique options are required.")
                                .font(.caption)
                                .foregroundStyle(condition.hasDuplicateOptions ? Color.red : Color.secondary)
                                .padding(.top, 8)
                        }
                    }
                    Divider().padding(.top, condition.kind == .noul ? 0 : 12)
                    Button("Delete Condition", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
#if os(iOS)
                    .padding(.vertical, 16)
#else
                    .padding(.vertical, 12)
#endif
                    .help("Delete this decision condition")
                }
                .background {
                    Color.primary.opacity(0.025).padding(.horizontal, -16)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: condition.kind)
        .onChange(of: condition.kind) { _, kind in
            if kind == .noul { focusedOptionID = nil }
            draggingOption = nil
        }
        .onChange(of: condition.options) { _, _ in
            let focusedIndex = condition.optionEntries.firstIndex { $0.id == focusedOptionID }
            withAnimation(.snappy(duration: 0.25)) {
                condition.normalizeOptions()
            }
            if let focusedID = focusedOptionID, !condition.optionEntries.contains(where: { $0.id == focusedID }) {
                focusedOptionID = condition.optionEntries[min(focusedIndex ?? 0, condition.optionEntries.count - 1)].id
            }
        }
    }

    private var optionRows: some View {
        VStack(spacing: 12) {
            ForEach(condition.optionEntries) { option in
                optionRow(optionBinding(for: option))
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.top, 12)
        .animation(.snappy(duration: 0.25), value: condition.optionEntries.map(\.id))
    }

    private var nativeScoreOptions: some View {
        return VStack(spacing: 12) {
            if !condition.optionEntries.isEmpty {
                List {
                    ForEach(condition.optionEntries) { option in
                        optionRowContent(optionBinding(for: option), showsHandle: false)
                            .frame(height: scoreRowHeight)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .moveDisabled(option.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onMove { source, destination in
                        condition.optionEntries.move(fromOffsets: source, toOffset: min(destination, condition.optionEntries.count - 1))
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .modifier(DecisionScoreEditMode())
                .frame(height: scoreRowHeight * CGFloat(condition.optionEntries.count))
            }
        }
    }

    private func optionBinding(for option: DecisionOption) -> Binding<DecisionOption> {
        Binding {
            condition.optionEntries.first { $0.id == option.id } ?? option
        } set: { updated in
            guard let index = condition.optionEntries.firstIndex(where: { $0.id == option.id }) else { return }
            condition.optionEntries[index] = updated
        }
    }

    private func optionRow(_ option: Binding<DecisionOption>) -> some View {
        optionRowContent(option)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { optionRowWidth = $0 }
            .onDrop(of: [DecisionScoreDrag.contentType], delegate: DecisionScoreDropDelegate(condition: $condition, draggingID: $draggingOption, destinationID: option.wrappedValue.id))
    }

    private func optionRowContent(_ option: Binding<DecisionOption>, showsHandle: Bool = true) -> some View {
        let index = condition.optionEntries.firstIndex(where: { $0.id == option.wrappedValue.id }) ?? 0
        let isEmpty = option.wrappedValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack {
            if condition.kind == .score {
                HStack {
                    if showsHandle { scoreDragHandle(option, isEmpty: isEmpty) }
                    Text("\(index)").monospacedDigit().frame(minWidth: 18)
                }
                .foregroundStyle(isEmpty ? .tertiary : .secondary)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            TextField("Option \(index + 1)", text: option.text, prompt: Text("Enter text to add an option…"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(6)
                .modifier(DecisionInputStyle())
                .accessibilityLabel("Option \(index + 1)")
                .focused($focusedOptionID, equals: option.wrappedValue.id)
#if os(iOS)
                .submitLabel(.next)
                .onSubmit {
                    guard !isEmpty else { return }
                    withAnimation(.snappy(duration: 0.25)) { condition.normalizeOptions() }
                    guard let currentIndex = condition.optionEntries.firstIndex(where: { $0.id == option.wrappedValue.id }),
                          condition.optionEntries.indices.contains(currentIndex + 1) else { return }
                    focusedOptionID = condition.optionEntries[currentIndex + 1].id
                }
#endif
            if !option.wrappedValue.text.isEmpty {
                Button {
                    let removedID = option.wrappedValue.id
                    withAnimation(.snappy(duration: 0.25)) {
                        condition.optionEntries.removeAll { $0.id == removedID }
                        condition.normalizeOptions()
                    }
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .padding(.leading, 4)
                .help("Remove option")
            }
        }
        .animation(.snappy(duration: 0.25), value: isEmpty)
    }

    @ViewBuilder
    private func scoreDragHandle(_ option: Binding<DecisionOption>, isEmpty: Bool) -> some View {
        let handle = Image(systemName: "line.3.horizontal")
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .help("Drag to reorder score levels")
        if isEmpty {
            handle
        } else {
            handle.onDrag {
                draggingOption = option.wrappedValue.id
                return DecisionScoreDrag.provider()
            } preview: {
                HStack {
                    Image(systemName: "line.3.horizontal")
                    Text("\(condition.optionEntries.firstIndex(where: { $0.id == option.wrappedValue.id }) ?? 0)")
                        .monospacedDigit()
                    Text(option.wrappedValue.text).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "xmark")
                }
                    .frame(width: max(0, optionRowWidth - 16))
                    .padding(8)
                    .background(scoreDragBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var scoreDragBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }
}

private struct DecisionScoreEditMode: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content.environment(\.editMode, .constant(.active))
#endif
    }
}

struct DecisionResultRow: View {
    let condition: DecisionCondition
    let answer: DecisionAnswer
    let number: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProbabilities = false

    private var probabilities: [(String, Double)] {
        if let probability = answer.noul { return [(String(localized: "Yes"), probability), (String(localized: "No"), 1 - probability)] }
        return condition.resultOptions(probabilities: answer.probabilities ?? [:]).enumerated().map { index, option in
            (condition.kind == .score ? "\(DecisionResultFormatter.points(index)) — \(option)" : option, answer.probabilities?[condition.kind == .score ? String(index) : option] ?? 0)
        }
    }
    private var winningIndex: Int? { probabilities.indices.max { probabilities[$0].1 < probabilities[$1].1 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(number). \(condition.instructions)")
                Spacer()
                Text(condition.kind.title).font(.caption).foregroundStyle(.secondary)
            }
            if let score = answer.score {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(score, format: .number.precision(.fractionLength(2))).font(.largeTitle).bold()
                        Text("/ \(DecisionResultFormatter.points(condition.validOptions.count - 1))").foregroundStyle(.secondary)
                    }
                    if let winner = winningIndex {
                        Text("Most likely: \(condition.validOptions[winner])").font(.body)
                    }
                }
                .padding(.bottom, 4)
            }
            VStack(spacing: resultOptionSpacing) {
                ForEach(probabilities.indices, id: \.self) { index in
                    let entry = probabilities[index]
                    VStack(spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.0)
                                .font(condition.kind != .score && index == winningIndex ? .title : .body)
                            Spacer()
                            Text(entry.1, format: .percent.precision(.fractionLength(0)))
                        }
                        .fontWeight(index == winningIndex ? .bold : .regular)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.12))
                                Capsule()
                                    .fill(index == winningIndex ? Color.accentColor : Color.gray)
                                    .frame(width: geometry.size.width * (showsProbabilities ? min(max(entry.1, 0), 1) : 0))
                            }
                        }
                        .frame(height: 6)
                        .accessibilityElement()
                        .accessibilityLabel(Text(entry.0))
                        .accessibilityValue(Text(entry.1, format: .percent.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .textSelection(.enabled)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                showsProbabilities = true
            }
        }
    }

    private var resultOptionSpacing: CGFloat {
#if os(iOS)
        14
#else
        8
#endif
    }
}

private struct DecisionScoreDropDelegate: DropDelegate {
    @Binding var condition: DecisionCondition
    @Binding var draggingID: UUID?
    let destinationID: UUID

    func validateDrop(info: DropInfo) -> Bool { condition.kind == .score && draggingID != nil }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingID else { return }
        withAnimation(.snappy(duration: 0.25)) {
            condition.moveOption(id: sourceID, to: destinationID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        let handled = condition.kind == .score && draggingID != nil
        draggingID = nil
        return handled
    }
}

struct DecisionConditionsEditor: View {
    @Binding var conditions: [DecisionCondition]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                VStack(spacing: 0) {
                    DecisionConditionEditor(condition: binding(for: condition), number: index + 1) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                            conditions.removeAll { $0.id == condition.id }
                        }
                    }
                    Divider().padding(.horizontal, -16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button("Add Condition", systemImage: "plus") {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    conditions.append(DecisionCondition())
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
#if os(iOS)
            .padding(.vertical, 16)
#else
            .padding(.vertical, 12)
#endif
            .help("Add a decision condition")
            .disabled(conditions.count >= 64)
        }
#if os(macOS)
        .padding(.vertical, -10)
#endif
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func binding(for condition: DecisionCondition) -> Binding<DecisionCondition> {
        Binding {
            conditions.first { $0.id == condition.id } ?? condition
        } set: { updated in
            guard let index = conditions.firstIndex(where: { $0.id == condition.id }) else { return }
            conditions[index] = updated
        }
    }
}

#Preview("Decision Conditions") {
    @Previewable @State var conditions = {
        var collapsed = DecisionCondition()
        collapsed.isExpanded = false
        return [DecisionCondition(), collapsed]
    }()
    Form {
        Section("Decision Conditions") {
            DecisionConditionsEditor(conditions: $conditions)
        }
    }
    .formStyle(.grouped)
#if os(macOS)
    .frame(width: 600, height: 600)
#endif
}

#Preview("Decision Results") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            DecisionResultRow(
                condition: DecisionCondition(instructions: "Classify this report.", options: ["Bug report", "Feature request"]),
                answer: DecisionAnswer(type: "choice", choice: "Bug report", noul: nil, score: nil, legend: nil, probabilities: ["Bug report": 0.92, "Feature request": 0.08], confidence: nil),
                number: 1)
            Divider()
            DecisionResultRow(
                condition: DecisionCondition(instructions: "Is this a bug report?", kind: .noul),
                answer: DecisionAnswer(type: "noul", choice: nil, noul: 0.81, score: nil, legend: nil, probabilities: nil, confidence: nil),
                number: 2)
            Divider()
            DecisionResultRow(
                condition: DecisionCondition(instructions: "Evaluate the severity.", kind: .score, options: ["Minor", "Low", "Medium", "High", "Critical"]),
                answer: DecisionAnswer(type: "score", choice: nil, noul: nil, score: 2.8, legend: nil, probabilities: ["0": 0.05, "1": 0.1, "2": 0.15, "3": 0.4, "4": 0.3], confidence: nil),
                number: 3)
        }
        .padding()
    }
#if os(macOS)
    .frame(width: 600, height: 750)
#endif
}

#Preview("Score Options") {
    @Previewable @State var conditions = [DecisionCondition(instructions: "Evaluate the severity.", kind: .score, options: ["Low", "Medium", "High", ""])]
    Form {
        Section("Decision Conditions") {
            DecisionConditionsEditor(conditions: $conditions)
        }
    }
    .formStyle(.grouped)
#if os(macOS)
    .frame(width: 600, height: 600)
#endif
}
