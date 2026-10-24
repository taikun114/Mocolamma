import Foundation
import UniformTypeIdentifiers

enum AudioAttachmentError: LocalizedError {
    case invalidWAV
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .conversionFailed:
            return String(localized: "This audio file could not be converted to WAV. The format may be unsupported or the file may be damaged.")
        case .invalidWAV:
            return String(localized: "This audio file cannot be attached. Use a valid PCM WAV file.")
        }
    }
}

/// 音声を画像やテキストと区別し、Ollamaが読み込めるWAVのみ受け付けます。
enum AudioAttachmentValidator {
    static func isAudioFile(url: URL, data: Data) -> Bool {
        let type = UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .audio) == true || hasWAVHeader(data)
    }

    static func create(data: Data, fileName: String) throws -> ChatInputAttachment {
        try validateWAV(data)
        return ChatInputAttachment(name: fileName, content: "", audioData: data)
    }

    static func validate(messages: [ChatMessage], supportsAudio: Bool) throws {
        guard supportsAudio else { return }
        let audioAttachments = messages.flatMap { $0.attachments ?? [] }.filter(\.isAudio)
        for attachment in audioAttachments {
            if let data = attachment.audioData {
                try validateWAV(data)
            }
        }
    }

    private static func hasWAVHeader(_ data: Data) -> Bool {
        data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WAVE".utf8)
    }

    static func validateWAV(_ data: Data) throws {
        guard hasWAVHeader(data) else { throw AudioAttachmentError.invalidWAV }
        func integer(at offset: Int, bytes: Int) -> Int {
            (0..<bytes).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        let end = integer(at: 4, bytes: 4) + 8
        guard end == data.count else { throw AudioAttachmentError.invalidWAV }
        var offset = 12
        var format: (code: Int, channels: Int, rate: Int, bits: Int, alignment: Int)?
        var sampleBytes: Int?
        while offset + 8 <= end {
            let size = integer(at: offset + 4, bytes: 4)
            let start = offset + 8
            guard size <= end - start else { throw AudioAttachmentError.invalidWAV }
            let chunk = data[offset..<(offset + 4)]
            if chunk == Data("fmt ".utf8) {
                guard size >= 16 else { throw AudioAttachmentError.invalidWAV }
                var code = integer(at: start, bytes: 2)
                if code == 0xfffe {
                    guard size >= 40 else { throw AudioAttachmentError.invalidWAV }
                    code = integer(at: start + 24, bytes: 2)
                }
                format = (code, integer(at: start + 2, bytes: 2), integer(at: start + 4, bytes: 4), integer(at: start + 14, bytes: 2), integer(at: start + 12, bytes: 2))
            } else if chunk == Data("data".utf8) {
                sampleBytes = size
            }
            offset = start + size + size % 2
        }
        guard let format, let sampleBytes, sampleBytes > 0,
              format.channels > 0, format.rate > 0,
              (format.code == 1 && [8, 16, 24, 32].contains(format.bits)) || (format.code == 3 && format.bits == 32),
              format.alignment == format.channels * (format.bits / 8),
              sampleBytes % format.alignment == 0 else {
            throw AudioAttachmentError.invalidWAV
        }
    }
}
