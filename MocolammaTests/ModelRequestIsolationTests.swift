import Foundation
import Testing
@testable import Mocolamma

private struct ModelAPIReply: Sendable {
    var status = 200
    var body: Data
}

private actor ModelAPIScript {
    static let shared = ModelAPIScript()
    private var heldKeys: Set<String> = []
    private var pending: [String: CheckedContinuation<ModelAPIReply, Error>] = [:]
    private var arrivals: [String: CheckedContinuation<Void, Never>] = [:]

    func hold(_ key: String) { heldKeys.insert(key) }
    func waitForPending(_ key: String) async {
        if pending[key] != nil { return }
        await withCheckedContinuation { arrivals[key] = $0 }
    }
    func release(_ key: String, fail: Bool = false) {
        let continuation = pending.removeValue(forKey: key)
        if fail { continuation?.resume(throwing: URLError(.timedOut)) }
        else { continuation?.resume(returning: reply(key)) }
    }
    func respond(_ request: URLRequest) async throws -> ModelAPIReply {
        let key = request.url!.host! + request.url!.path
        if heldKeys.remove(key) != nil {
            return try await withCheckedThrowingContinuation {
                pending[key] = $0
                arrivals.removeValue(forKey: key)?.resume()
            }
        }
        return reply(key)
    }
    private func reply(_ key: String) -> ModelAPIReply {
        let name = key.hasPrefix("alpha.invalid") ? "alpha-model" : "beta-model"
        let capability = key.hasPrefix("alpha.invalid") ? "completion" : "vision"
        let text: String
        if key.hasSuffix("/api/tags") {
            text = "{\"models\":[{\"name\":\"\(name)\",\"model\":\"\(name)\",\"modified_at\":\"\",\"size\":1,\"digest\":\"test\"}]}"
        } else if key.hasSuffix("/api/show") {
            text = "{\"capabilities\":[\"\(capability)\"]}"
        } else {
            text = "{\"models\":[{\"name\":\"\(name)\"}]}"
        }
        return ModelAPIReply(body: Data(text.utf8))
    }
}

private final class ModelAPIProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            do {
                let reply = try await ModelAPIScript.shared.respond(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct ModelRequestIsolationTests {
    private func makeExecutor() throws -> (CommandExecutor, ServerManager, ServerInfo, ServerInfo) {
        let defaults = try #require(UserDefaults(suiteName: "ModelRequestTests.\(UUID())"))
        let manager = ServerManager(defaults: defaults)
        let alpha = ServerInfo(name: "Alpha", host: "alpha.invalid")
        let beta = ServerInfo(name: "Beta", host: "beta.invalid")
        manager.servers = [alpha, beta]
        manager.selectedServerID = alpha.id
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModelAPIProtocol.self]
        return (CommandExecutor(serverManager: manager, sessionConfiguration: config, monitorsDrag: false), manager, alpha, beta)
    }

    @Test func lateDetailsCannotReplaceAnotherServersListOrCache() async throws {
        let (executor, manager, _, beta) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/show")
        let old = Task { await executor.fetchOllamaModelsFromAPI() }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/show")
        manager.selectedServerID = beta.id
        executor.invalidateModelRequests()
        await executor.fetchOllamaModelsFromAPI()
        await ModelAPIScript.shared.release("alpha.invalid/api/show")
        await old.value
        #expect(executor.models.map(\.name) == ["beta-model"])
        #expect(executor.models.first?.capabilities == ["vision"])
        #expect(executor.getCachedModelInfo(modelName: "alpha-model") == nil)
        #expect(executor.initialFetchCompleted && !executor.apiConnectionError)
    }

    @Test func lateFailureCannotClearNewServersSuccess() async throws {
        let (executor, manager, _, beta) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/tags")
        let old = Task { await executor.fetchOllamaModelsFromAPI() }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/tags")
        manager.selectedServerID = beta.id
        executor.invalidateModelRequests()
        await executor.fetchOllamaModelsFromAPI()
        let output = executor.output
        await ModelAPIScript.shared.release("alpha.invalid/api/tags", fail: true)
        await old.value
        #expect(executor.models.map(\.name) == ["beta-model"])
        #expect(executor.output == output)
        #expect(!executor.apiConnectionError && !executor.isRunning)
    }

    @Test func returningToSameServerRejectsOldDetailsAndCacheIsScoped() async throws {
        let (executor, manager, alpha, beta) = try makeExecutor()
        #expect(await executor.fetchModelInfo(modelName: "shared")?.capabilities == ["completion"])
        manager.selectedServerID = beta.id
        #expect(executor.getCachedModelInfo(modelName: "shared") == nil)
        #expect(await executor.fetchModelInfo(modelName: "shared")?.capabilities == ["vision"])
        await ModelAPIScript.shared.hold("beta.invalid/api/show")
        let old = Task { await executor.fetchModelInfo(modelName: "other") }
        await ModelAPIScript.shared.waitForPending("beta.invalid/api/show")
        manager.selectedServerID = alpha.id
        manager.selectedServerID = beta.id
        await ModelAPIScript.shared.release("beta.invalid/api/show")
        #expect(await old.value == nil)
        #expect(executor.getCachedModelInfo(modelName: "other") == nil)
    }

    @Test func runningModelsFromOldOrInspectedServerDoNotOverwriteSelection() async throws {
        let (executor, manager, _, beta) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/ps")
        let old = Task { await executor.fetchRunningModels() }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/ps")
        manager.selectedServerID = beta.id
        _ = await executor.fetchRunningModels()
        await ModelAPIScript.shared.release("alpha.invalid/api/ps")
        _ = await old.value
        #expect(executor.runningModels.map(\.name) == ["beta-model"])
        let inspected = await executor.fetchRunningModels(host: "alpha.invalid")
        #expect(inspected?.map(\.name) == ["alpha-model"])
        #expect(executor.runningModels.map(\.name) == ["beta-model"])
    }

    @Test func obsoleteRequestCannotEndNewLoadingAndHostEditsInvalidateContext() async throws {
        let (executor, manager, alpha, _) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/tags")
        let old = Task { await executor.fetchOllamaModelsFromAPI() }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/tags")
        await ModelAPIScript.shared.hold("alpha.invalid/api/show")
        let newer = Task { await executor.fetchOllamaModelsFromAPI() }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/show")
        await ModelAPIScript.shared.release("alpha.invalid/api/tags")
        await old.value
        #expect(executor.isRunning)
        await ModelAPIScript.shared.release("alpha.invalid/api/show")
        await newer.value
        #expect(!executor.isRunning && executor.models.count == 1)
        let context = executor.modelRequestContext
        var edited = alpha
        edited.host = "updated.invalid"
        manager.updateServer(serverInfo: edited)
        #expect(executor.modelRequestContext != context)
    }

    @Test func refreshingCacheRejectsAnAlreadyRunningDetailResponse() async throws {
        let (executor, _, _, _) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/show")
        let old = Task { await executor.fetchModelInfo(modelName: "shared") }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/show")
        executor.clearModelInfoCache()
        let refreshed = await executor.fetchModelInfo(modelName: "shared")
        await ModelAPIScript.shared.release("alpha.invalid/api/show")
        #expect(await old.value == nil)
        #expect(executor.getCachedModelInfo(modelName: "shared")?.capabilities == refreshed?.capabilities)
    }

    @Test func oldLoadCompletionCannotClearAnotherServersLoadingIndicator() async throws {
        let (executor, manager, _, beta) = try makeExecutor()
        await ModelAPIScript.shared.hold("alpha.invalid/api/generate")
        let old = Task { await executor.loadModel(modelName: "shared") }
        await ModelAPIScript.shared.waitForPending("alpha.invalid/api/generate")
        manager.selectedServerID = beta.id
        executor.invalidateModelRequests()
        await ModelAPIScript.shared.hold("beta.invalid/api/generate")
        let newer = Task { await executor.loadModel(modelName: "shared") }
        await ModelAPIScript.shared.waitForPending("beta.invalid/api/generate")
        await ModelAPIScript.shared.release("alpha.invalid/api/generate")
        _ = await old.value
        #expect(executor.loadingModelNames.contains("shared"))
        #expect(executor.recentLoadedModelNames.isEmpty)
        await ModelAPIScript.shared.release("beta.invalid/api/generate")
        #expect(await newer.value)
        #expect(executor.loadingModelNames.isEmpty)
        #expect(executor.recentLoadedModelNames.contains("shared"))
    }
}
