import Foundation
import Testing
@testable import Mocolamma

@MainActor
private final class HeldConnectionReply {
    private var reply: CheckedContinuation<ServerConnectionStatus, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func fetch() async -> ServerConnectionStatus {
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

    func release(_ status: ServerConnectionStatus) {
        reply?.resume(returning: status)
        reply = nil
    }
}

@MainActor
struct ServerConnectionPollingTests {
    private func makeManager() throws -> (ServerManager, ServerInfo, ServerInfo) {
        let defaults = try #require(UserDefaults(suiteName: "ServerConnectionPollingTests.\(UUID())"))
        let manager = ServerManager(defaults: defaults)
        let alpha = ServerInfo(name: "Alpha", host: "alpha.invalid")
        let beta = ServerInfo(name: "Beta", host: "beta.invalid")
        manager.servers = [alpha, beta]
        manager.selectedServerID = alpha.id
        return (manager, alpha, beta)
    }

    @Test func checksImmediatelyThenEveryFiveSecondsWithoutClearingLastStatus() async throws {
        let (manager, alpha, _) = try makeManager()
        var calls = 0
        var intervals: [Duration] = []
        await manager.pollConnection(for: alpha, check: { host in
            #expect(host == alpha.host)
            if calls == 0 { #expect(intervals.isEmpty) }
            else { #expect(manager.serverConnectionStatuses[alpha.id]?.isConnected == true) }
            calls += 1
            return calls == 1 ? .connected : .notConnected(statusCode: -1004)
        }, sleep: { interval in
            intervals.append(interval)
            if intervals.count == 2 { throw CancellationError() }
        })
        #expect(calls == 2)
        #expect(intervals == [.seconds(5), .seconds(5)])
        #expect(manager.serverConnectionStatuses[alpha.id]?.isConnected == false)
    }

    @Test func returningToServerScreenChecksAgainBeforeWaiting() async throws {
        let (manager, alpha, _) = try makeManager()
        var calls = 0
        for _ in 0..<2 {
            var hasChecked = false
            await manager.pollConnection(for: alpha, check: { _ in
                hasChecked = true
                calls += 1
                return .connected
            }, sleep: { _ in
                #expect(hasChecked)
                throw CancellationError()
            })
        }
        #expect(calls == 2)
    }

    @Test func delayedServerDoesNotBlockOtherServerChecksOrChangeSelection() async throws {
        let (manager, alpha, beta) = try makeManager()
        let held = HeldConnectionReply()
        let slow = Task {
            await manager.pollConnection(for: alpha, check: { _ in await held.fetch() }, sleep: { _ in throw CancellationError() })
        }
        await held.waitForRequest()
        await manager.pollConnection(for: beta, check: { _ in .connected }, sleep: { _ in throw CancellationError() })
        #expect(manager.serverConnectionStatuses[beta.id]?.isConnected == true)
        #expect(manager.selectedServerID == alpha.id)
        held.release(.timedOut)
        await slow.value
    }

    @Test func cancelledPollingCannotPublishPendingResult() async throws {
        let (manager, alpha, _) = try makeManager()
        manager.updateServerConnectionStatus(serverID: alpha.id, status: .connected)
        let held = HeldConnectionReply()
        let pending = Task {
            await manager.pollConnection(for: alpha, check: { _ in await held.fetch() }, sleep: { _ in throw CancellationError() })
        }
        await held.waitForRequest()
        pending.cancel()
        held.release(.timedOut)
        await pending.value
        #expect(manager.serverConnectionStatuses[alpha.id]?.isConnected == true)
    }

    @Test func newerCheckWinsOverDelayedEarlierCheck() async throws {
        let (manager, alpha, _) = try makeManager()
        let held = HeldConnectionReply()
        let old = Task { await manager.checkConnection(for: alpha) { _ in await held.fetch() } }
        await held.waitForRequest()
        await manager.checkConnection(for: alpha) { _ in .connected }
        held.release(.timedOut)
        await old.value
        #expect(manager.serverConnectionStatuses[alpha.id]?.isConnected == true)
    }

    @Test func deletingServerCannotRecreateItsIndicatorFromPendingReply() async throws {
        let (manager, alpha, _) = try makeManager()
        let held = HeldConnectionReply()
        let old = Task { await manager.checkConnection(for: alpha) { _ in await held.fetch() } }
        await held.waitForRequest()
        manager.deleteServer(alpha)
        held.release(.connected)
        await old.value
        #expect(manager.serverConnectionStatuses[alpha.id] == nil)
    }

    @Test func editingHostAndRestoringItStillRejectsEarlierCheck() async throws {
        let (manager, alpha, _) = try makeManager()
        let held = HeldConnectionReply()
        let old = Task { await manager.checkConnection(for: alpha) { _ in await held.fetch() } }
        await held.waitForRequest()
        var edited = alpha
        edited.host = "edited.invalid"
        manager.updateServer(serverInfo: edited)
        manager.updateServer(serverInfo: alpha)
        held.release(.connected)
        await old.value
        #expect(manager.serverConnectionStatuses[alpha.id]?.isConnected == false)
    }
}
