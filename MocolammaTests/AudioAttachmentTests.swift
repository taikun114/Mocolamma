import Foundation
import Testing
@testable import Mocolamma

struct AudioAttachmentTests {
    private func wav(sampleCount: UInt32 = 1, sampleRate: UInt32 = 16000) -> Data {
        var data = Data("RIFF".utf8)
        func append(_ value: UInt32, bytes: Int) {
            for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        append(36 + sampleCount * 2, bytes: 4)
        data.append(Data("WAVEfmt ".utf8))
        append(16, bytes: 4)
        append(1, bytes: 2)
        append(1, bytes: 2)
        append(sampleRate, bytes: 4)
        append(sampleRate * 2, bytes: 4)
        append(2, bytes: 2)
        append(16, bytes: 2)
        data.append(Data("data".utf8))
        append(sampleCount * 2, bytes: 4)
        data.append(Data(repeating: 0, count: Int(sampleCount) * 2))
        return data
    }

    @Test func audioPrecedesImagesAndPDFPages() throws {
        let data = wav()
        let audio = try AudioAttachmentValidator.create(data: data, fileName: "recording.WAV")
        let message = ChatMessage(role: "user", content: "Describe", images: ["image"], pdfImages: ["page"], attachments: [ChatInputAttachment(name: "notes.txt", content: "Notes"), audio])
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        #expect(payload["images"] as? [String] == [data.base64EncodedString(), "image", "page"])
        #expect(message.images == ["image"])
        #expect(message.promptForAPI.contains("Attached Audio 1: recording.WAV"))
        #expect(message.promptForAPI.contains("Notes"))
    }

    @Test func audioFilenameAndDataSurviveAttachmentRoundTrip() throws {
        let audio = try AudioAttachmentValidator.create(data: wav(), fileName: "voice.M4A")
        let restored = try JSONDecoder().decode(ChatInputAttachment.self, from: JSONEncoder().encode(audio))
        #expect(restored.audioData == wav())
        #expect(restored.isAudio)
        #expect(restored.name == "voice.M4A")
        #expect(ChatMessage.buildFullPrompt(userText: "", attachments: [restored]) == "===\n\nAttached Audio 1: voice.M4A")
        try AudioAttachmentValidator.validate(messages: [ChatMessage(role: "user", content: "", attachments: [restored])], supportsAudio: true)
    }

    @Test func unsupportedModelOmitsAudioFromEntireHistory() throws {
        let audio = try AudioAttachmentValidator.create(data: wav(), fileName: "voice.wav")
        let original = ChatMessage(role: "user", content: "Describe", images: ["image"], pdfImages: ["page"], attachments: [audio])
        let messages = [original, ChatMessage(role: "user", content: "Continue")]
        try AudioAttachmentValidator.validate(messages: messages, supportsAudio: false)
        let encoder = JSONEncoder()
        encoder.userInfo[.includesAudioAttachments] = false
        let payload = try #require(JSONSerialization.jsonObject(with: encoder.encode(messages)) as? [[String: Any]])
        #expect(payload[0]["images"] as? [String] == ["image", "page"])
        #expect(payload[0]["content"] as? String == "Describe")
        #expect(payload[1]["content"] as? String == "Continue")
        #expect(original.attachments?.first?.audioData == wav())
    }

    @Test func sendingWithoutAudioRemovesItAndKeepsOtherAttachments() throws {
        let audio = try AudioAttachmentValidator.create(data: wav(), fileName: "recording.mp3")
        let notes = ChatInputAttachment(name: "notes.txt", content: "Notes")
        let submission = ChatAttachmentSendPolicy.prepare(images: [], attachments: [audio, notes], skipImages: false, skipAudio: true)
        let message = ChatMessage(role: "user", content: "Summarize", images: ["image"], attachments: submission.attachments)
        message.rawInputAttachments = submission.attachments
        try AudioAttachmentValidator.validate(messages: [message], supportsAudio: true)
        let omitted = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        #expect(omitted["images"] as? [String] == ["image"])
        #expect(omitted["content"] as? String == ChatMessage.buildFullPrompt(userText: "Summarize", attachments: [notes]))
        #expect(!message.promptForAPI.contains("Attached Audio"))
        #expect(message.attachments?.map(\.name) == ["notes.txt"])
        #expect(message.rawInputAttachments?.map(\.name) == ["notes.txt"])
    }

    @Test func audioOnlyOmissionSendsOriginalTextWithoutMedia() throws {
        let audio = try AudioAttachmentValidator.create(data: wav(), fileName: "voice.wav")
        let submission = ChatAttachmentSendPolicy.prepare(images: [], attachments: [audio], skipImages: false, skipAudio: true)
        let message = ChatMessage(role: "user", content: "Hello", attachments: submission.attachments)
        message.rawInputAttachments = submission.attachments
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        #expect(payload["content"] as? String == "Hello")
        #expect(payload["images"] == nil)
        #expect((message.attachments ?? message.rawInputAttachments ?? []).isEmpty)
    }

    @Test func audioLongerThanTenMinutesIsSentWithoutTrimming() async throws {
        let data = wav(sampleCount: 8000 * 601, sampleRate: 8000)
        let audio = try await AudioAttachmentConverter.prepare(data: data, fileName: "long-recording.wav")
        let message = ChatMessage(role: "user", content: "Transcribe", attachments: [audio])
        try AudioAttachmentValidator.validate(messages: [message], supportsAudio: true)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        #expect(payload["images"] as? [String] == [data.base64EncodedString()])
        #expect(audio.audioData == data)
    }

    @Test func audioNamesMatchAudioPayloadOrderWithMixedAttachments() throws {
        let firstData = wav(sampleCount: 2)
        let secondData = wav(sampleCount: 3)
        let first = try AudioAttachmentValidator.create(data: firstData, fileName: "meeting.m4a")
        let second = try AudioAttachmentValidator.create(data: secondData, fileName: "interview.mp3")
        let notes = ChatInputAttachment(name: "notes.txt", content: "Notes")
        let message = ChatMessage(role: "user", content: "Compare", images: ["image"], pdfImages: ["page"], attachments: [notes, first, notes, second])
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let prompt = try #require(payload["content"] as? String)
        #expect(payload["images"] as? [String] == [firstData.base64EncodedString(), secondData.base64EncodedString(), "image", "page"])
        let firstLabel = try #require(prompt.range(of: "Attached Audio 1: meeting.m4a"))
        let secondLabel = try #require(prompt.range(of: "Attached Audio 2: interview.mp3"))
        #expect(firstLabel.lowerBound < secondLabel.lowerBound)
        #expect(!prompt.contains(firstData.base64EncodedString()))
        #expect(!prompt.contains(secondData.base64EncodedString()))
        #expect(message.content == "Compare")
    }

    @Test func malformedAndUnsupportedAudioAreRejected() {
        var truncated = wav()
        truncated.removeLast()
        var compressed = wav()
        compressed[20] = 6
        var empty = wav()
        empty[40] = 0
        for invalid in [Data(), Data("ID3 audio".utf8), truncated, compressed, empty] {
            #expect(throws: AudioAttachmentError.self) { try AudioAttachmentValidator.validateWAV(invalid) }
        }
        #expect(AudioAttachmentValidator.isAudioFile(url: URL(fileURLWithPath: "/tmp/clip.mp3"), data: Data()))
        #expect(AudioAttachmentValidator.isAudioFile(url: URL(fileURLWithPath: "/tmp/clip.bin"), data: wav()))
    }

    @Test func legacyAttachmentStillDecodes() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"notes.txt\",\"content\":\"Notes\"}".utf8)
        let attachment = try JSONDecoder().decode(ChatInputAttachment.self, from: legacy)
        #expect(!attachment.isAudio)
        #expect(attachment.content == "Notes")
    }
}
