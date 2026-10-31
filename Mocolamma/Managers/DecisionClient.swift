import Foundation

struct DecisionClient {
    func evaluate(baseURL: String, body: Data, timeout: TimeInterval) async throws -> (response: DecisionResponse, elapsed: TimeInterval) {
        let address = baseURL.contains("://") ? baseURL : "http://\(baseURL)"
        guard let base = URL(string: address), ["http", "https"].contains(base.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("v1/systemone"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout > 0 ? timeout : 604_800
        configuration.timeoutIntervalForResource = 604_800
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: request)
        let duration = start.duration(to: clock.now).components
        let elapsed = TimeInterval(duration.seconds) + TimeInterval(duration.attoseconds) / 1e18
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw DecisionError.server(http.statusCode, error?["error"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return (try JSONDecoder().decode(DecisionResponse.self, from: data), elapsed)
    }
}
