import Foundation
import Testing
@testable import Mocolamma

struct StopButtonCooldownTests {
    @Test func stopIsBlockedUntilOneSecondHasElapsed() throws {
        let start = ContinuousClock().now
        var cooldown = StopButtonCooldown()
        #expect(cooldown.canStop(at: start))
        cooldown.begin(at: start)
        #expect(cooldown.isLocked)
        #expect(!cooldown.canStop(at: start))
        #expect(!cooldown.canStop(at: start.advanced(by: .milliseconds(999))))
        #expect(cooldown.canStop(at: start.advanced(by: .seconds(1))))
        cooldown.release(ifDeadline: try #require(cooldown.deadline))
        #expect(!cooldown.isLocked)
    }

    @Test func completionClearsCooldownImmediately() throws {
        let start = ContinuousClock().now
        var cooldown = StopButtonCooldown()
        cooldown.begin(at: start)
        let oldDeadline = try #require(cooldown.deadline)
        cooldown.reset()
        #expect(!cooldown.isLocked)
        #expect(cooldown.canStop(at: start.advanced(by: .milliseconds(100))))
        cooldown.release(ifDeadline: oldDeadline)
        #expect(!cooldown.isLocked)
    }

    @Test func previousRequestCannotUnlockNewRequest() throws {
        let start = ContinuousClock().now
        var cooldown = StopButtonCooldown()
        cooldown.begin(at: start)
        let oldDeadline = try #require(cooldown.deadline)
        cooldown.reset()
        let nextStart = start.advanced(by: .milliseconds(200))
        cooldown.begin(at: nextStart)
        let newDeadline = try #require(cooldown.deadline)
        cooldown.release(ifDeadline: oldDeadline)
        #expect(cooldown.isLocked)
        #expect(!cooldown.canStop(at: oldDeadline))
        #expect(cooldown.canStop(at: newDeadline))
        cooldown.release(ifDeadline: newDeadline)
        #expect(!cooldown.isLocked)
    }
}
