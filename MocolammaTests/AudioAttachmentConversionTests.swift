import AVFoundation
import Foundation
import Testing
@testable import Mocolamma

private final class AudioFixtureBundle: NSObject {}

struct AudioAttachmentConversionTests {
    @Test(arguments: ["mp3", "m4a", "aiff", "flac"])
    func convertsAudioToPCMWithoutChangingRateOrChannels(fileExtension: String) async throws {
        let bundle = Bundle(for: AudioFixtureBundle.self)
        let source = try #require(bundle.url(forResource: "AudioConversionTone", withExtension: fileExtension)
            ?? bundle.url(forResource: "AudioConversionTone", withExtension: fileExtension, subdirectory: "AudioFixtures"))
        let sourceData = try Data(contentsOf: source)
        let attachment = try await AudioAttachmentConverter.prepare(data: sourceData, fileName: source.lastPathComponent)
        let wav = try #require(attachment.audioData)
        try AudioAttachmentValidator.validateWAV(wav)
        #expect(attachment.name == source.lastPathComponent)
        #expect(attachment.content.isEmpty)
        #expect(try Data(contentsOf: source) == sourceData)

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: destination) }
        try wav.write(to: destination)
        let output = try AVAudioFile(forReading: destination)
        #expect(output.fileFormat.sampleRate == 44100)
        #expect(output.fileFormat.channelCount == 2)
        #expect(output.fileFormat.commonFormat == .pcmFormatInt16)
        let expectedDuration = fileExtension == "aiff" ? 0.75 : 0.25
        #expect(abs(Double(output.length) / 44100 - expectedDuration) < 0.05)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 4096))
        try output.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        #expect((0..<Int(buffer.frameLength)).contains { abs(channel[$0]) > 0.01 })

        let message = ChatMessage(role: "user", content: "Describe", images: ["image"], attachments: [attachment])
        try AudioAttachmentValidator.validate(messages: [message], supportsAudio: true)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        #expect(payload["images"] as? [String] == [wav.base64EncodedString(), "image"])
        #expect((payload["content"] as? String)?.contains("Attached Audio 1: \(source.lastPathComponent)") == true)
    }

    @Test func unreadableAudioReportsConversionFailure() async throws {
        do {
            _ = try await AudioAttachmentConverter.prepare(data: Data("invalid audio".utf8), fileName: "broken.mp3")
            Issue.record("読み込めない音声の変換が成功として扱われました")
        } catch AudioAttachmentError.conversionFailed {
        }
    }
}
