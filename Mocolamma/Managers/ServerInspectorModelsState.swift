import Foundation
import Observation

@Observable @MainActor
final class ServerInspectorModelsState {
    private(set) var host: String?
    private(set) var models: [OllamaRunningModel] = []
    private(set) var isLoading = false
    private var contextID = UUID()
    private var requestID = UUID()

    func poll(host: String,
              fetch: @MainActor (String) async -> [OllamaRunningModel]?,
              sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        let context = UUID()
        contextID = context
        self.host = host
        models = []
        isLoading = true
        defer {
            if contextID == context { stop() }
        }
        while !Task.isCancelled, contextID == context {
            await refresh(host: host, fetch: fetch)
            guard !Task.isCancelled, contextID == context else { return }
            do {
                try await sleep(.seconds(5))
            } catch {
                return
            }
        }
    }

    func refresh(host: String, fetch: @MainActor (String) async -> [OllamaRunningModel]?) async {
        guard self.host == host, !Task.isCancelled else { return }
        let context = contextID
        let request = UUID()
        requestID = request
        let result = await fetch(host)
        guard !Task.isCancelled, self.host == host, contextID == context, requestID == request else { return }
        models = result ?? []
        isLoading = false
    }

    func stop() {
        contextID = UUID()
        requestID = UUID()
        host = nil
        isLoading = false
    }
}
