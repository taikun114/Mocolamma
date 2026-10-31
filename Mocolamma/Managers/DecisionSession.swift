import SwiftUI
import Observation

@Observable @MainActor
final class DecisionSession {
    var selectedModelID: String?
    var input = ""
    var isJSON = false
    var images: [ChatInputImage] = []
    var attachments: [ChatInputAttachment] = []
    var conditions = [DecisionCondition()]
    var keepAliveOption: KeepAliveOption = .default
    var customKeepAliveValue = 5
    var customKeepAliveUnit: KeepAliveUnit = .minutes
    var resultRevision = UUID()
    var result: DecisionResponse?
    var resultConditions: [DecisionCondition] = []
    var elapsed: TimeInterval = 0
    var isRunning = false
    var error: String?
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    var isJSONInvalid: Bool { isJSON && (try? DecisionRequestBuilder.state(text: input, json: true)) == nil }
    var hasInput: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty || !attachments.isEmpty }
    var hasDraft: Bool {
        hasInput || isJSON || result != nil || conditions.count != 1 || conditions.contains {
            !$0.instructions.isEmpty || $0.kind != .choice || $0.options.contains { !$0.isEmpty } || !$0.isExpanded
        }
    }
    var canEvaluate: Bool {
        selectedModelID != nil && hasInput && !isJSONInvalid && !isRunning && !conditions.isEmpty && conditions.allSatisfy(\.isValid) &&
        !images.contains(where: \.isLoading) && !attachments.contains(where: \.isLoading)
    }

    func canEvaluate(model: OllamaModel) -> Bool {
        guard canEvaluate else { return false }
        return model.supportsVision || images.isEmpty ||
            !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachments.contains { !$0.isAudio || model.supportsAudio }
    }

    func reset() {
        cancel()
        images.forEach { $0.loadTask?.cancel() }
        attachments.forEach { $0.loadTask?.cancel() }
        input = ""
        isJSON = false
        images = []
        attachments = []
        conditions = [DecisionCondition()]
        result = nil
        resultConditions = []
        error = nil
        elapsed = 0
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    func evaluate(baseURL: String, model: OllamaModel, skipImages: Bool = false, onSuccess: @escaping @MainActor () -> Void = {}) {
        guard canEvaluate(model: model) else { return }
        let id = UUID()
        requestID = id
        let snapshot = conditions
        let text = input
        let json = isJSON
        let files = attachments
        let pictures = skipImages ? [] : images
        let keepAlive = keepAliveOption.apiValue(customValue: customKeepAliveValue, customUnit: customKeepAliveUnit)
        isRunning = true
        error = nil
        task = Task {
            do {
                if (!pictures.isEmpty && !model.supportsVision) || (files.contains(where: \.isAudio) && !model.supportsAudio) {
                    throw DecisionError.unsupportedAttachments
                }
                let processed = await files.resolveProcessedAttachments(renderImages: model.supportsVision && !skipImages)
                let direct = await pictures.resolveBase64Images()
                let audio = processed.attachments.compactMap { $0.audioData?.base64EncodedString() }
                let media = audio + direct + processed.pdfPageImages
                let state: JSONValue
                if json {
                    guard files.isEmpty else { throw DecisionError.unsupportedAttachments }
                    state = try DecisionRequestBuilder.state(text: text, json: true)
                } else {
                    let prompt = ChatMessage.buildFullPrompt(userText: text, attachments: processed.attachments, directImageCount: direct.count, pdfImageCount: processed.pdfPageImages.count)
                    state = .string(prompt)
                }
                let body = try DecisionRequestBuilder.body(model: model.name, state: state, images: media, conditions: snapshot, keepAlive: keepAlive)
                let measured = try await DecisionClient().evaluate(baseURL: baseURL, body: body, timeout: APITimeoutManager.shared.currentOption.requestTimeoutUntilFirstByte)
                try Task.checkCancellation()
                guard requestID == id else { return }
                let response = measured.response
                result = response
                resultConditions = snapshot
                elapsed = measured.elapsed
                resultRevision = UUID()
                onSuccess()
#if DEBUG
                print("Decision request completed: \(response.answers.count) answers in \(elapsed) seconds")
#endif
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
#if DEBUG
                print("Decision request failed: \(error.localizedDescription)")
#endif
            }
            if requestID == id { isRunning = false; task = nil }
        }
    }
}
