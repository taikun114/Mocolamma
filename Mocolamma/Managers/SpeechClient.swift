import Foundation

actor SpeechClient {
    func generate(request: URLRequest, timeout: TimeInterval, onChunk: @MainActor @Sendable (Data) throws -> Void) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout > 0 ? timeout : 604_800
        configuration.timeoutIntervalForResource = 604_800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 65_536 { break }
            }
            throw SpeechRequestBuilder.serverError(status: http.statusCode, data: body)
        }
        guard http.mimeType?.lowercased() == "audio/pcm" else { throw SpeechError.invalidAudio }
        var chunk = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if chunk.count >= 4096 {
                try await onChunk(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty { try await onChunk(chunk) }
        try Task.checkCancellation()
    }
}
