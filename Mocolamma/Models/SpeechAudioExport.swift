import AVFAudio
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct SpeechAudioExport: Transferable, Sendable {
    let id: UUID
    let pcm: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .wav) { audio in
            SentTransferredFile(try await audio.fileURL())
        }
        .suggestedFileName("Speech.wav")
    }

    func fileURL() async throws -> URL {
        try await SpeechAudioExportStore.shared.fileURL(for: self)
    }
}

private actor SpeechAudioExportStore {
    static let shared = SpeechAudioExportStore()

    func fileURL(for audio: SpeechAudioExport) throws -> URL {
        guard !audio.pcm.isEmpty, audio.pcm.count.isMultiple(of: 2) else { throw SpeechError.invalidAudio }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechExports", isDirectory: true)
            .appendingPathComponent(audio.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Speech.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try write(audio.pcm, to: url)
            // クリップボードや共有先が後から読むため、履歴を消去しても一時ファイルは保持する。
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            print("Speech audio export failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func write(_ pcm: Data, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: SpeechPCMStream.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384),
              let samples = buffer.int16ChannelData?[0] else { throw SpeechError.invalidAudio }
        try pcm.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw SpeechError.invalidAudio }
            var offset = 0
            while offset < pcm.count {
                let count = min(Int(buffer.frameCapacity) * 2, pcm.count - offset)
                memcpy(samples, base.advanced(by: offset), count)
                buffer.frameLength = AVAudioFrameCount(count / 2)
                try file.write(from: buffer)
                offset += count
            }
        }
    }
}
