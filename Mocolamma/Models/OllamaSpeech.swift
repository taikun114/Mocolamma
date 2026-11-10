import Foundation

struct SpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let response_format = "pcm"
}

enum SpeechError: LocalizedError {
    case emptyInput, invalidAudio
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return String(localized: "Enter text to generate speech.")
        case .invalidAudio:
            return String(localized: "The server returned invalid or incomplete audio.")
        case .server(let status, let message):
            return String(localized: "Speech API Error (\(status)): \(message)")
        }
    }
}

enum SpeechRequestBuilder {
    static func request(baseURL: String, model: String, input: String, voice: String) throws -> URLRequest {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SpeechError.emptyInput }
        let address = baseURL.contains("://") ? baseURL : "http://\(baseURL)"
        guard let base = URL(string: address), base.host != nil,
              ["http", "https"].contains(base.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechRequest(model: model, input: input, voice: voice))
        return request
    }

    static func voices(from voices: [String]?) -> [String] {
        var seen: Set<String> = ["default"]
        return ["default"] + (voices ?? []).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func serverError(status: Int, data: Data) -> SpeechError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = object?["error"] as? [String: Any]
        let message = nested?["message"] as? String ?? object?["error"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: status)
        return .server(status, message)
    }
}

struct SpeechPCMStream {
    static let sampleRate = 24_000.0
    private(set) var data = Data()
    private var pendingByte: UInt8?

    var duration: TimeInterval { Double(data.count) / (Self.sampleRate * 2) }

    mutating func append(_ chunk: Data) -> Data {
        var aligned = Data()
        if let pendingByte { aligned.append(pendingByte) }
        aligned.append(chunk)
        pendingByte = aligned.count.isMultiple(of: 2) ? nil : aligned.removeLast()
        data.append(aligned)
        return aligned
    }

    func finish() throws {
        guard !data.isEmpty, pendingByte == nil else { throw SpeechError.invalidAudio }
    }
}
