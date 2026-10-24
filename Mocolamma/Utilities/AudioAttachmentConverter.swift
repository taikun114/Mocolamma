import AVFoundation
import Foundation

/// OSが読み込める音声を、サンプルレートとチャンネル数を維持したPCM WAVに変換します。
enum AudioAttachmentConverter {
    static func prepare(data: Data, fileName: String) async throws -> ChatInputAttachment {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            if (try? AudioAttachmentValidator.validateWAV(data)) != nil {
                return try AudioAttachmentValidator.create(data: data, fileName: fileName)
            }

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    print("Failed to remove temporary audio conversion files: \(error.localizedDescription)")
                }
            }
            let source = directory.appendingPathComponent("source").appendingPathExtension((fileName as NSString).pathExtension)
            let destination = directory.appendingPathComponent("converted.wav")
            do {
                try data.write(to: source)
                try transcode(source: source, destination: destination)
                try Task.checkCancellation()
                let converted = try Data(contentsOf: destination)
                let attachment = try AudioAttachmentValidator.create(data: converted, fileName: fileName)
                print("Audio conversion completed: \(data.count) input bytes, \(converted.count) WAV bytes")
                return attachment
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("Audio conversion failed: \(error.localizedDescription)")
                throw AudioAttachmentError.conversionFailed
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func transcode(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        // 固定サイズのバッファで読み書きし、展開後の音声全体をメモリに保持しません。
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384) else {
            throw AudioAttachmentError.conversionFailed
        }
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        while input.framePosition < input.length {
            try Task.checkCancellation()
            let remaining = input.length - input.framePosition
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, AVAudioFramePosition(buffer.frameCapacity))))
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
        // 関数を抜けてファイルを閉じてから、呼び出し側でWAVデータを読み込みます。
    }
}
