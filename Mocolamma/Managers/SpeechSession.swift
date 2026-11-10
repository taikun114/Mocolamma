import Foundation
import Observation

@Observable @MainActor
final class SpeechSession {
    var selectedModelID: String?
    var selectedVoice = "default"
    private(set) var voices = ["default"]
    var input = ""
    var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    var error: String?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var context: ModelRequestContext?

    func changeServer(_ newContext: ModelRequestContext) {
        guard newContext != context else { return }
        clear()
        context = newContext
        selectedModelID = nil
        resetVoices()
    }

    func resetVoices() {
        voices = ["default"]
        selectedVoice = "default"
    }

    func setVoices(_ values: [String]?) {
        voices = SpeechRequestBuilder.voices(from: values)
        if !voices.contains(selectedVoice) { selectedVoice = "default" }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        for message in messages where message.isStreaming {
            message.isStreaming = false
            message.isStopped = true
            message.speechPlayback?.cancelReceiving()
        }
        isGenerating = false
    }

    func clear() {
        cancel()
        messages.forEach { $0.stopSpeechRevisions() }
        messages = []
        input = ""
        error = nil
    }

    func generate(baseURL: String, model: OllamaModel, retryID: UUID? = nil, onModelLoaded: @escaping @MainActor () -> Void = {}) {
        guard !isGenerating, model.supportsSpeech else { return }
        var prompt = input
        var replacingIndex: Int?
        if let retryID, let index = messages.firstIndex(where: { $0.id == retryID }) {
            let userIndex = messages[index].role == "user" ? index : index - 1
            guard userIndex >= 0, messages[userIndex].role == "user" else { return }
            prompt = messages[userIndex].content
            replacingIndex = userIndex + 1
        }
        let request: URLRequest
        do { request = try SpeechRequestBuilder.request(baseURL: baseURL, model: model.name, input: prompt, voice: selectedVoice) }
        catch { self.error = error.localizedDescription; return }
        messages.forEach { $0.speechPlayback?.pause() }
        var revisions: [ChatMessage] = []
        var previousPlayback: SpeechPlayback?
        if let replacingIndex {
            if replacingIndex < messages.count {
                previousPlayback = messages[replacingIndex].speechPlayback
                revisions = messages[replacingIndex].speechRevisionsForRetry()
                messages.dropFirst(replacingIndex + 1).forEach { $0.stopSpeechRevisions() }
                messages.removeSubrange(replacingIndex...)
            }
        } else {
            let user = ChatMessage(role: "user", content: prompt, createdAt: MessageView.iso8601Formatter.string(from: Date()))
            user.isSpeechGeneration = true
            messages.append(user)
            input = ""
        }
        let message = ChatMessage(role: "assistant", content: "", createdAt: MessageView.iso8601Formatter.string(from: Date()), isStreaming: true)
        message.isSpeechGeneration = true
        message.speechVoice = selectedVoice
        message.speechModelName = model.name
        message.revisions = revisions
        message.currentRevisionIndex = revisions.count
        let playback = SpeechPlayback()
        if let previousPlayback { playback.inheritVolume(from: previousPlayback) }
        message.speechPlayback = playback
        messages.append(message)
        isGenerating = true
        error = nil
        let id = UUID()
        requestID = id
        let timeout = APITimeoutManager.shared.currentOption.requestTimeoutUntilFirstByte
        task = Task {
            let start = ContinuousClock.now
            do {
                try await SpeechClient().generate(request: request, timeout: timeout) { @MainActor [weak self, weak playback] chunk in
                    guard let self, let playback, self.requestID == id, !Task.isCancelled else { throw CancellationError() }
                    let isFirstAudio = !playback.hasAudio
                    try playback.append(chunk)
                    if isFirstAudio && playback.hasAudio { onModelLoaded() }
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                try playback.finish()
                let elapsed = start.duration(to: .now).components
                message.totalDuration = Int(elapsed.seconds) * 1_000_000_000 + Int(elapsed.attoseconds / 1_000_000_000)
#if DEBUG
                print("Speech generation completed: \(playback.duration ?? 0) seconds of audio")
#endif
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                handleGenerationError(error, for: message)
#if DEBUG
                print("Speech generation failed: \(error.localizedDescription)")
#endif
            }
            guard requestID == id else { return }
            message.isStreaming = false
            isGenerating = false
            task = nil
        }
    }

    func handleGenerationError(_ error: Error, for message: ChatMessage) {
        message.speechPlayback?.cancelReceiving()
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            message.isStopped = true
            return
        }
        var description = error.localizedDescription
        if (error as? URLError)?.code == .timedOut {
            description += "\n\n" + String(localized: "If it takes time to load large models, increasing the API timeout in Mocolamma settings or changing it to unlimited may help.")
        }
        message.isStopped = false
        message.content = description
        self.error = description
    }
}
