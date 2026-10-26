import Foundation

/// 送信直後の連続クリックで停止しないよう、単調増加時計で停止可能時刻を管理します。
struct StopButtonCooldown {
    private(set) var deadline: ContinuousClock.Instant?

    var isLocked: Bool { deadline != nil }

    mutating func begin(at now: ContinuousClock.Instant = ContinuousClock().now) {
        deadline = now.advanced(by: .seconds(1))
    }

    func canStop(at now: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        guard let deadline else { return true }
        return now >= deadline
    }

    mutating func release(ifDeadline expected: ContinuousClock.Instant) {
        guard deadline == expected else { return }
        deadline = nil
    }

    mutating func reset() {
        deadline = nil
    }
}
