import Foundation
import Testing
@testable import Mocolamma

@MainActor
private final class HeldInspectorModels {
    private var reply: CheckedContinuation<[OllamaRunningModel]?, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func fetch() async -> [OllamaRunningModel]? {
        await withCheckedContinuation {
            reply = $0
            arrival?.resume()
            arrival = nil
        }
    }

    func waitForRequest() async {
        if reply != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release(_ models: [OllamaRunningModel]) {
        reply?.resume(returning: models)
        reply = nil
    }
}

@MainActor
struct ServerInspectorModelsTests {
    private func models(_ name: String) -> [OllamaRunningModel] {
        [.init(name: name, expires_at: nil, size_vram: 1024)]
    }

    @Test func pollsEveryFiveSecondsAndKeepsDisplayedModelsUntilNextResult() async {
        let state = ServerInspectorModelsState()
        var requests = 0
        var intervals: [Duration] = []
        await state.poll(host: "alpha.invalid", fetch: { host in
            #expect(host == "alpha.invalid")
            if requests == 1 {
                #expect(state.models.map(\.name) == ["first"])
                #expect(!state.isLoading)
            }
            requests += 1
            return self.models(requests == 1 ? "first" : "second")
        }, sleep: { interval in
            intervals.append(interval)
            if intervals.count == 2 { throw CancellationError() }
        })
        #expect(requests == 2)
        #expect(intervals == [.seconds(5), .seconds(5)])
        #expect(state.models.map(\.name) == ["second"])
    }

    @Test(arguments: ["beta.invalid", "alpha.invalid"])
    func delayedReplyCannotReplaceNewInspectorEvenWhenReturningToSameHost(newHost: String) async {
        let state = ServerInspectorModelsState()
        let held = HeldInspectorModels()
        let old = Task {
            await state.poll(host: "alpha.invalid", fetch: { _ in await held.fetch() }, sleep: { _ in throw CancellationError() })
        }
        await held.waitForRequest()
        await state.poll(host: newHost, fetch: { _ in self.models("new-result") }, sleep: { _ in throw CancellationError() })
        held.release(models("obsolete"))
        await old.value
        #expect(state.models.map(\.name) == ["new-result"])
    }

    @Test func newerManualRefreshWinsOverDelayedPollingReply() async {
        let state = ServerInspectorModelsState()
        let held = HeldInspectorModels()
        let old = Task {
            await state.poll(host: "alpha.invalid", fetch: { _ in await held.fetch() }, sleep: { _ in throw CancellationError() })
        }
        await held.waitForRequest()
        await state.refresh(host: "alpha.invalid") { _ in self.models("manual-result") }
        held.release(models("obsolete"))
        await old.value
        #expect(state.models.map(\.name) == ["manual-result"])
    }

    @Test func closingInspectorRejectsOutstandingReply() async {
        let state = ServerInspectorModelsState()
        let held = HeldInspectorModels()
        let pending = Task {
            await state.poll(host: "alpha.invalid", fetch: { _ in await held.fetch() }, sleep: { _ in throw CancellationError() })
        }
        await held.waitForRequest()
        state.stop()
        held.release(models("obsolete"))
        await pending.value
        #expect(state.models.isEmpty)
        #expect(state.host == nil)
        #expect(!state.isLoading)
    }
}
