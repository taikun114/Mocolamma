import Foundation
import AVFAudio
import Testing
@testable import Mocolamma

struct SpeechTests {
    @Test func screenshotSpeechPromptsDescribeMocolammaInEachLanguage() {
        #expect(ScreenshotConfiguration.speechModelName == "lfm3-audio:2b")
        let english = ScreenshotConfiguration.speechPrompt(language: "en-US")
        let japanese = ScreenshotConfiguration.speechPrompt(language: "ja-JP")
        #expect(english.hasPrefix("Mocolamma is an application"))
        #expect(english.contains("macOS, iOS, iPadOS, and visionOS"))
        #expect(japanese.hasPrefix("Mocolammaは、Ollamaサーバーと接続して"))
        #expect(japanese.contains("macOS、iOS、iPadOS、visionOS"))
        for language in ["de-DE", "fr-FR", "zh-Hans", ""] {
            #expect(ScreenshotConfiguration.speechPrompt(language: language) == english)
        }
        #expect(english.components(separatedBy: "\n\n").count == 2)
        #expect(japanese.components(separatedBy: "\n\n").count == 2)
    }

    @Test @MainActor func exportsBufferedAudioAsWAVWithOriginalSamplesAndReusesFile() async throws {
        let playback = SpeechPlayback()
        #expect(playback.audioExport == nil)
        var pcm = Data()
        for index in 0..<20_000 {
            var sample = Int16(index - 10_000).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        try playback.append(pcm)
        #expect(playback.audioExport == nil)
        try playback.finish()
        let audio = try #require(playback.audioExport)
        let url = try await audio.fileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repeatedURL = try await audio.fileURL()
        #expect(url == repeatedURL)
        #expect(url.pathExtension == "wav")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        #expect(file.length == 20_000)
        #expect(file.fileFormat.sampleRate == 24_000)
        #expect(file.fileFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 20_000))
        try file.read(into: buffer)
        let samples = try #require(buffer.int16ChannelData?[0])
        #expect(Data(bytes: samples, count: Int(buffer.frameLength) * 2) == pcm)
        playback.setVolume(0)
        playback.stop()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test @MainActor func stoppedAudioCanBeExportedAndInvalidExportIsRejected() async throws {
        let playback = SpeechPlayback()
        try playback.append(Data([1, 0, 2, 0, 3]))
        playback.cancelReceiving()
        let audio = try #require(playback.audioExport)
        #expect(audio.pcm == Data([1, 0, 2, 0]))
        await #expect(throws: SpeechError.self) { try await SpeechAudioExport(id: UUID(), pcm: Data()).fileURL() }
        await #expect(throws: SpeechError.self) { try await SpeechAudioExport(id: UUID(), pcm: Data([1])).fileURL() }
    }

    @Test func buildsPCMRequestWithoutUnsupportedOptions() throws {
        let request = try SpeechRequestBuilder.request(baseURL: "localhost:11434", model: "lfm3-audio:2b", input: "こんにちは。", voice: "female-japanese")
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/audio/speech")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["model": "lfm3-audio:2b", "input": "こんにちは。", "voice": "female-japanese", "response_format": "pcm"])
    }

    @Test func longInputIsSentUnchangedWhileRejectingEmptyInputAndInvalidURL() throws {
        #expect(throws: SpeechError.self) { try SpeechRequestBuilder.request(baseURL: "localhost:11434", model: "test", input: " \n", voice: "default") }
        let combined = String(repeating: "e\u{301}", count: 2048)
        _ = try SpeechRequestBuilder.request(baseURL: "https://example.com/ollama", model: "test", input: combined, voice: "default")
        let input = combined + String(repeating: "a", count: 5000)
        let request = try SpeechRequestBuilder.request(baseURL: "localhost:11434", model: "test", input: input, voice: "default")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body["input"] == input)
        #expect(throws: URLError.self) { try SpeechRequestBuilder.request(baseURL: "file:///tmp/test", model: "test", input: "a", voice: "default") }
    }

    @Test func preservesVoiceOrderAndAddsSingleDefault() throws {
        let response = try JSONDecoder().decode(OllamaShowResponse.self, from: Data(#"{"voices":["male-japanese","default","female-japanese","male-japanese"]}"#.utf8))
        #expect(SpeechRequestBuilder.voices(from: response.voices) == ["default", "male-japanese", "female-japanese"])
        #expect(SpeechRequestBuilder.voices(from: nil) == ["default"])
    }

    @Test func buffersSplitSamplesAndRejectsTruncatedAudio() throws {
        var stream = SpeechPCMStream()
        #expect(stream.append(Data([0x01])).isEmpty)
        #expect(stream.append(Data([0x02, 0x03, 0x04, 0x05])) == Data([1, 2, 3, 4]))
        #expect(throws: SpeechError.self) { try stream.finish() }
        #expect(stream.append(Data([0x06])) == Data([5, 6]))
        try stream.finish()
        #expect(stream.data == Data([1, 2, 3, 4, 5, 6]))
        #expect(stream.duration == 3 / 24_000.0)
        #expect(throws: SpeechError.self) { try SpeechPCMStream().finish() }
    }

    @Test func readsOpenAIAndNativeErrorBodies() {
        let nested = SpeechRequestBuilder.serverError(status: 400, data: Data(#"{"error":{"message":"instructions are not supported","type":"invalid_request_error","param":null,"code":null}}"#.utf8))
        if case .server(let status, let message) = nested {
            #expect(status == 400)
            #expect(message == "instructions are not supported")
        } else { Issue.record("Expected server error") }
        let native = SpeechRequestBuilder.serverError(status: 500, data: Data(#"{"error":"test failure"}"#.utf8))
        if case .server(_, let message) = native { #expect(message == "test failure") }
        else { Issue.record("Expected server error") }
    }
    @Test @MainActor func receivedAudioStaysPausedAndCanSeekWithinGrowingBuffer() throws {
        let playback = SpeechPlayback()
        #expect(!playback.isPlaying)
        try playback.append(Data(repeating: 0, count: 48_000))
        #expect(playback.hasAudio)
        #expect(playback.bufferedDuration == 1)
        #expect(playback.duration == nil)
        #expect(!playback.isPlaying)
        try playback.seek(to: 0.75)
        #expect(playback.currentTime == 0.75)
        try playback.append(Data(repeating: 0, count: 48_000))
        #expect(playback.bufferedDuration == 2)
        #expect(playback.currentTime == 0.75)
        try playback.seek(to: 20)
        #expect(playback.currentTime == 2)
        try playback.finish()
        #expect(playback.duration == 2)
        #expect(playback.isAtEnd)
        #expect(!playback.isReceiving)
        #expect(!playback.isPlaying)
    }

    @Test @MainActor func mutePreservesVolumeAndRestoresZeroVolume() {
        let playback = SpeechPlayback()
        playback.setVolume(0.25)
        #expect(playback.volumeSymbol == "speaker.wave.3.fill")
        playback.toggleMute()
        #expect(playback.isMuted)
        #expect(playback.volume == 0.25)
        #expect(playback.volumeSymbol == "speaker.slash.fill")
        playback.toggleMute()
        #expect(!playback.isMuted)
        #expect(playback.volume == 0.25)
        playback.setVolume(0)
        #expect(playback.volumeSymbol == "speaker.slash.fill")
        playback.toggleMute()
        #expect(playback.volume == 0.25)
        playback.setVolume(2)
        #expect(playback.volume == 1)
        #expect(playback.volumeSymbol == "speaker.wave.3.fill")
    }

    @Test func scrubbingUsesRelativeMovementAndClampsToBuffer() {
        #expect(MediaScrubPosition.relative(origin: 30, translation: 0, width: 200, duration: 100) == 30)
        #expect(MediaScrubPosition.relative(origin: 30, translation: 20, width: 200, duration: 100) == 40)
        #expect(MediaScrubPosition.relative(origin: 30, translation: -20, width: 200, duration: 100) == 20)
        #expect(MediaScrubPosition.relative(origin: 30, translation: -200, width: 200, duration: 100) == 0)
        #expect(MediaScrubPosition.relative(origin: 30, translation: 200, width: 200, duration: 100) == 100)
    }

    @Test @MainActor func pausedPositionSurvivesAdditionalAudioAndRepeatedPause() throws {
        let playback = SpeechPlayback()
        try playback.append(Data(repeating: 0, count: 48_000))
        try playback.seek(to: 0.75)
        playback.pause()
        #expect(playback.currentTime == 0.75)
        try playback.append(Data(repeating: 0, count: 48_000))
        playback.pause()
        #expect(playback.currentTime == 0.75)
        #expect(playback.bufferedDuration == 2)
        #expect(!playback.isAtEnd)
        try playback.finish()
        #expect(playback.currentTime == 0.75)
        try playback.seek(to: 2)
        playback.pause()
        #expect(playback.currentTime == 2)
        #expect(playback.isAtEnd)
    }

    @Test @MainActor func speechRevisionsResetPositionAndShareVolumeWhilePreservingLatestResult() throws {
        let first = ChatMessage(role: "assistant", content: "", createdAt: "2026-01-01T00:00:00Z")
        first.isSpeechGeneration = true
        first.totalDuration = 100
        first.speechVoice = "male-japanese"
        first.speechModelName = "example-speech:2b"
        let firstPlayback = SpeechPlayback()
        try firstPlayback.append(Data(repeating: 0, count: 48_000))
        try firstPlayback.finish()
        try firstPlayback.seek(to: 0.25)
        first.speechPlayback = firstPlayback

        let second = ChatMessage(role: "assistant", content: "", createdAt: "2026-01-01T00:01:00Z")
        second.isSpeechGeneration = true
        second.totalDuration = 200
        second.speechVoice = "default"
        second.speechModelName = "example-speech:4b"
        let secondPlayback = SpeechPlayback()
        try secondPlayback.append(Data(repeating: 0, count: 96_000))
        try secondPlayback.finish()
        try secondPlayback.seek(to: 1.5)
        secondPlayback.setVolume(0.4)
        secondPlayback.toggleMute()
        second.speechPlayback = secondPlayback
        second.revisions = first.speechRevisionsForRetry()
        second.currentRevisionIndex = second.revisions.count

        second.selectSpeechRevision(at: 0)
        #expect(second.speechPlayback === firstPlayback)
        #expect(second.speechPlayback?.currentTime == 0)
        #expect(firstPlayback.volume == 0.4)
        #expect(firstPlayback.isMuted)
        #expect(second.createdAt == first.createdAt)
        #expect(second.totalDuration == 100)
        #expect(second.speechVoice == "male-japanese")
        #expect(second.speechModelName == "example-speech:2b")
        let history = second.speechRevisionsForRetry()
        #expect(history.count == 2)
        #expect(history[0].speechPlayback === firstPlayback)
        #expect(history[1].speechPlayback === secondPlayback)
        #expect(history[1].totalDuration == 200)
        #expect(history[1].speechVoice == "default")
        #expect(history[1].speechModelName == "example-speech:4b")

        firstPlayback.setVolume(0.7)
        second.selectSpeechRevision(at: 1)
        #expect(second.speechPlayback === secondPlayback)
        #expect(second.speechPlayback?.currentTime == 0)
        #expect(secondPlayback.volume == 0.7)
        #expect(!secondPlayback.isMuted)
        #expect(second.totalDuration == 200)
        #expect(second.speechVoice == "default")
        #expect(second.speechModelName == "example-speech:4b")
        second.selectSpeechRevision(at: -1)
        second.selectSpeechRevision(at: 2)
        #expect(second.currentRevisionIndex == 1)
        #expect(second.revisions[0].speechPlayback === firstPlayback)
    }

    @Test @MainActor func generationErrorsPopulateBothMessageAndAlertWhileCancellationStaysSilent() {
        let session = SpeechSession()
        let message = ChatMessage(role: "assistant", content: "")
        message.speechPlayback = SpeechPlayback()
        let apiError = SpeechError.server(400, "Example API error")
        session.handleGenerationError(apiError, for: message)
        #expect(message.content == apiError.localizedDescription)
        #expect(session.error == message.content)
        #expect(!message.isStopped)
        #expect(message.speechPlayback?.isReceiving == false)

        session.error = nil
        session.handleGenerationError(URLError(.timedOut), for: message)
        #expect(session.error == message.content)
        #expect(message.content.contains(URLError(.timedOut).localizedDescription))
        #expect(message.content.contains(String(localized: "If it takes time to load large models, increasing the API timeout in Mocolamma settings or changing it to unlimited may help.")))

        session.error = nil
        message.content = ""
        session.handleGenerationError(URLError(.cancelled), for: message)
        #expect(session.error == nil)
        #expect(message.content.isEmpty)
        #expect(message.isStopped)
    }

    @Test @MainActor func speechRevisionKeepsFailedAndStoppedResultsAndClearsAllPlayers() {
        let stopped = ChatMessage(role: "assistant", content: "")
        stopped.isSpeechGeneration = true
        stopped.isStopped = true
        stopped.speechPlayback = SpeechPlayback()
        let failed = ChatMessage(role: "assistant", content: "Example error")
        failed.isSpeechGeneration = true
        failed.speechPlayback = SpeechPlayback()
        failed.revisions = stopped.speechRevisionsForRetry()
        failed.currentRevisionIndex = 1
        failed.isStreaming = true
        failed.selectSpeechRevision(at: 0)
        #expect(failed.currentRevisionIndex == 1)
        failed.isStreaming = false
        failed.selectSpeechRevision(at: 0)
        #expect(failed.isStopped)
        failed.selectSpeechRevision(at: 1)
        #expect(failed.content == "Example error")
        #expect(!failed.isStopped)

        let session = SpeechSession()
        session.messages = [failed]
        session.clear()
        #expect(session.messages.isEmpty)
        #expect(stopped.speechPlayback?.isReceiving == false)
        #expect(failed.latestSpeechRevision?.speechPlayback?.isReceiving == false)
    }
}
